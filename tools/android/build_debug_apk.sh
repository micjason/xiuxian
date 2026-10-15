#!/usr/bin/env bash
# 导出调试签名的 APK（可直接装到手机）。先运行一次 setup_toolchain.sh。
# 用法：
#   tools/android/build_debug_apk.sh [--api-base http://192.168.1.20:8080] [--out /path/xiuxian-debug.apk]
# - 在临时目录里拷一份 game/ 再导出，不会在仓库里留下 android/build、不会改你的工程设置。
# - --api-base 只是“默认服务器地址”，写进包里的工程设置；玩家随时可以在登录页「服务器地址」里改，
#   所以不填也行（默认 http://10.0.2.2:8080，是 Android 模拟器访问宿主机的地址）。
# - 允许明文 http（局域网里的开发服务器没有 https）：构建时给 AndroidManifest 加 usesCleartextTraffic。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HOME/android-toolchain}"
GODOT_HOME="${GODOT_HOME:-$HOME}"
GODOT="${GODOT:-godot}"
API_BASE="http://10.0.2.2:8080"
OUT="$ROOT/builds/development/xiuxian-debug.apk"

while [ $# -gt 0 ]; do
	case "$1" in
		--api-base) API_BASE="$2"; shift 2 ;;
		--out) OUT="$2"; shift 2 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

export JAVA_HOME="$TOOLCHAIN/jdk"
export ANDROID_HOME="$TOOLCHAIN/sdk"
export ANDROID_SDK_ROOT="$TOOLCHAIN/sdk"
export PATH="$JAVA_HOME/bin:$PATH"
export HOME="$GODOT_HOME"
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$TOOLCHAIN/debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/game"
(cd "$ROOT/game" && tar --exclude=./.godot --exclude=./android/build --exclude=./tests --exclude='./addons/gut' -cf - .) | tar -xf - -C "$WORK/game"

# 默认服务器地址写进工程设置
sed -i "s|^network/api_base_url=.*|network/api_base_url=\"$API_BASE\"|" "$WORK/game/project.godot"

# 导入资源（第一次会生成 .godot 缓存），再装 Android 构建模板
"$GODOT" --headless --path "$WORK/game" --import >/dev/null 2>&1 || true
# 装 Android 构建模板：把导出模板里的 android_source.zip 解到 android/build（等价于编辑器里“安装构建模板”）。
# 注意：--install-android-build-template 单独用时会卡住，所以这里手动解压。
TEMPLATE_ZIP="$GODOT_HOME/.local/share/godot/export_templates/$("$GODOT" --version | sed -E 's/^([0-9.]+)\.(stable).*/\1.\2/')/android_source.zip"
mkdir -p "$WORK/game/android/build"
unzip -q -o "$TEMPLATE_ZIP" -d "$WORK/game/android/build"
touch "$WORK/game/android/build/.gdignore"
"$GODOT" --version | sed -E 's/^([0-9.]+)\.(stable).*/\1.\2/' > "$WORK/game/android/.build_version"

# 允许明文 http（局域网开发服务器）
MANIFEST="$WORK/game/android/build/AndroidManifest.xml"
[ -f "$MANIFEST" ] || MANIFEST="$WORK/game/android/build/src/main/AndroidManifest.xml"
sed -i 's|<application|<application android:usesCleartextTraffic="true"|' "$MANIFEST"

mkdir -p "$(dirname "$OUT")"
"$GODOT" --headless --path "$WORK/game" --export-debug Android "$OUT"
ls -l "$OUT"
