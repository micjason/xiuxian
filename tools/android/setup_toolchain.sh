#!/usr/bin/env bash
# 在没有 Android 开发环境的 Linux 机器上，一次性装好“导出调试 APK”需要的东西：
#   JDK 17、Android SDK（platform-tools / platforms;android-35 / build-tools）、Godot 导出模板、调试签名密钥。
# 全部装在 $TOOLCHAIN（默认 ~/android-toolchain），不碰系统。可重复运行，已有的会跳过。
# 用法：  GODOT_VERSION=4.7.2 TOOLCHAIN=~/android-toolchain tools/android/setup_toolchain.sh
set -euo pipefail

TOOLCHAIN="${TOOLCHAIN:-$HOME/android-toolchain}"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GODOT_HOME="${GODOT_HOME:-$HOME}"          # Godot 的 HOME（编辑器设置、导出模板放在它下面）
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip}"
JDK_URL="${JDK_URL:-https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse}"
TEMPLATES_URL="${TEMPLATES_URL:-https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz}"

mkdir -p "$TOOLCHAIN"
cd "$TOOLCHAIN"

fetch() { # fetch URL FILE
	[ -s "$2" ] || curl -fsSL -o "$2" "$1"
}

# 1) JDK 17
if [ ! -x jdk/bin/java ]; then
	fetch "$JDK_URL" jdk17.tar.gz
	mkdir -p jdk && tar xzf jdk17.tar.gz -C jdk --strip-components=1
fi
export JAVA_HOME="$TOOLCHAIN/jdk"
export PATH="$JAVA_HOME/bin:$PATH"

# 2) Android SDK
if [ ! -x sdk/cmdline-tools/latest/bin/sdkmanager ]; then
	fetch "$CMDLINE_TOOLS_URL" cmdline-tools.zip
	mkdir -p sdk/cmdline-tools
	unzip -q -o cmdline-tools.zip -d sdk/cmdline-tools
	rm -rf sdk/cmdline-tools/latest
	mv sdk/cmdline-tools/cmdline-tools sdk/cmdline-tools/latest
fi
yes | sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root="$TOOLCHAIN/sdk" --licenses >/dev/null 2>&1 || true
sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root="$TOOLCHAIN/sdk" "platform-tools" "platforms;android-35" "build-tools;35.0.1" "build-tools;34.0.0" >/dev/null

# 3) Godot 导出模板（和编辑器版本号必须完全一致）
TEMPLATE_DIR="$GODOT_HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
if [ ! -f "$TEMPLATE_DIR/android_source.zip" ]; then
	fetch "$TEMPLATES_URL" templates.tpz
	mkdir -p tpl "$TEMPLATE_DIR"
	unzip -q -o templates.tpz -d tpl
	cp -r tpl/templates/* "$TEMPLATE_DIR/"
fi

# 4) 调试签名密钥（只用于调试包；不要提交，.gitignore 已排除 *.keystore）
if [ ! -f debug.keystore ]; then
	keytool -genkeypair -v -keystore debug.keystore -storepass android -keypass android \
		-alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

# 5) 写 Godot 编辑器设置（SDK、JDK、调试密钥路径）
SETTINGS_DIR="$GODOT_HOME/.config/godot"
SETTINGS="$SETTINGS_DIR/editor_settings-${GODOT_VERSION%.*}.tres"
mkdir -p "$SETTINGS_DIR"
[ -f "$SETTINGS" ] || printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' > "$SETTINGS"
set_setting() { # set_setting KEY VALUE
	sed -i "\|^$1 = |d" "$SETTINGS"
	printf '%s = "%s"\n' "$1" "$2" >> "$SETTINGS"
}
set_setting export/android/java_sdk_path "$TOOLCHAIN/jdk"
set_setting export/android/android_sdk_path "$TOOLCHAIN/sdk"
set_setting export/android/debug_keystore "$TOOLCHAIN/debug.keystore"
set_setting export/android/debug_keystore_user androiddebugkey
set_setting export/android/debug_keystore_pass android

echo "toolchain ready in $TOOLCHAIN"
