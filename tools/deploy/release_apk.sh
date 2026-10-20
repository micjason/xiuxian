#!/usr/bin/env bash
# 打一个新的 dev2 安装包并发布到服务器（客户端启动时会看到「发现新版本」）。在盒子上运行。
#
#   DEPLOY_HOST=101.132.74.32 tools/deploy/release_apk.sh [--version-name 0.11.1] [--notes "更新说明"] [--force] [--no-upload]
#
# 做的事：
#   1. versionCode +1，versionName 自动把最后一位 +1（或用 --version-name）；写回 game/export_presets.cfg 和 game/project.godot
#      （包名 com.micjason.xiuxian.dev2、应用名「修仙 测试版」，和老的正式包并存）。改完记得提交。
#   2. 在临时目录拷一份 game/，默认服务器地址写成 $APK_SERVER（默认 http://101.132.74.32:8090），允许明文 http，
#      用固定的签名密钥导出 release 包（以后每次更新都必须用同一个密钥，否则手机不能覆盖安装）。
#   3. apksigner 校验签名，生成 latest.json（versionCode / versionName / url / sha256 / size / notes / force），
#      通过 deploy.sh publish-apk 上传（--no-upload 只在本机生成）。
# 签名密钥：$SIGNING_DIR/xiuxian-dev2-release.keystore（不在仓库里），第一次运行自动生成；
#           密码在同目录 .pass 文件（只有自己能读）。备份：/workspace/.deploy/signing-backup/。丢了就再也不能覆盖安装了。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-/workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64}"
TOOLCHAIN="${TOOLCHAIN:-/workspace/android_toolchain}"
GODOT_HOME="${GODOT_HOME:-/workspace/.deploy/godot_home}"
SIGNING_DIR="${SIGNING_DIR:-/workspace/secrets/android}"
SIGNING_BACKUP="${SIGNING_BACKUP:-/workspace/.deploy/signing-backup}"
KEYSTORE="$SIGNING_DIR/xiuxian-dev2-release.keystore"
KEY_ALIAS="xiuxian-dev2"
APK_SERVER="${APK_SERVER:-http://101.132.74.32:8090}"
PUBLIC_URL="${DEPLOY_PUBLIC_URL:-$APK_SERVER}"
PACKAGE_ID="com.micjason.xiuxian.dev2"
APP_LABEL="修仙 测试版"
OUT_DIR="${APK_OUT_DIR:-/workspace/.deploy/apk}"
PRESETS="$ROOT/game/export_presets.cfg"
PROJECT="$ROOT/game/project.godot"
say() { printf '\033[1;35m[安装包]\033[0m %s\n' "$*"; }
oops() { printf '\033[1;31m[出错]\033[0m %s\n' "$*" >&2; exit 1; }

NAME_ARG=""
NOTES="${RELEASE_NOTES:-}"
FORCE=false
UPLOAD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --version-name) NAME_ARG="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --no-upload) UPLOAD=0; shift ;;
    *) oops "不认识的参数：$1" ;;
  esac
done
[ "$UPLOAD" = "0" ] || [ -n "${DEPLOY_HOST:-}" ] || oops "要上传就设 DEPLOY_HOST（或加 --no-upload）。"
export JAVA_HOME="$TOOLCHAIN/jdk" ANDROID_HOME="$TOOLCHAIN/sdk" ANDROID_SDK_ROOT="$TOOLCHAIN/sdk"
export PATH="$JAVA_HOME/bin:$PATH"
BUILD_TOOLS="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
[ -x "$BUILD_TOOLS/apksigner" ] || oops "没找到 apksigner（$ANDROID_HOME/build-tools）。先运行 tools/android/setup_toolchain.sh。"

# ---------------------------------------------------------------- 1. 签名密钥（只生成一次）
if [ ! -f "$KEYSTORE" ]; then
  say "第一次运行：生成签名密钥 $KEYSTORE（以后所有更新都用它）"
  mkdir -p "$SIGNING_DIR" && chmod 700 "$SIGNING_DIR"
  (umask 077; openssl rand -base64 30 | tr -dc 'A-Za-z0-9' | cut -c1-28 >"$KEYSTORE.pass")
  keytool -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 -alias "$KEY_ALIAS" -keyalg RSA -keysize 4096 -validity 36500 \
    -storepass:file "$KEYSTORE.pass" -dname "CN=Xiuxian dev2, O=Xiuxian, C=CN" >/dev/null 2>&1
  chmod 600 "$KEYSTORE"
fi
mkdir -p "$SIGNING_BACKUP" && chmod 700 "$SIGNING_BACKUP"
cmp -s "$KEYSTORE" "$SIGNING_BACKUP/$(basename "$KEYSTORE")" || install -m 600 "$KEYSTORE" "$KEYSTORE.pass" "$SIGNING_BACKUP/"
CERT_SHA="$(keytool -list -v -keystore "$KEYSTORE" -storepass:file "$KEYSTORE.pass" -alias "$KEY_ALIAS" 2>/dev/null | awk '/SHA256:/ {print $2; exit}')"

# ---------------------------------------------------------------- 2. 版本号
get_preset() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$PRESETS" | head -1; }
OLD_CODE="$(get_preset 'version\/code')"
OLD_NAME="$(get_preset 'version\/name')"
CODE=$((OLD_CODE + 1))
if [ -n "$NAME_ARG" ]; then VNAME="$NAME_ARG"
else
  base="${OLD_NAME%%-*}"
  case "$base" in *.*.*) VNAME="${base%.*}.$(( ${base##*.} + 1 ))" ;; *) VNAME="$base.1" ;; esac
fi
[[ "$VNAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || oops "versionName 要是 x.y.z：$VNAME"
say "版本 $OLD_NAME（$OLD_CODE）→ $VNAME（$CODE），包名 $PACKAGE_ID，默认服务器 $APK_SERVER"
set_preset() { sed -i "s|^$1=.*|$1=$2|" "$PRESETS"; }
set_preset 'version/code' "$CODE"
set_preset 'version/name' "\"$VNAME\""
set_preset 'package/unique_name' "\"$PACKAGE_ID\""
set_preset 'package/name' "\"$APP_LABEL\""
sed -i "s|^config/version=.*|config/version=\"$VNAME\"|" "$PROJECT"
if grep -q '^build/version_code=' "$PROJECT"; then sed -i "s|^build/version_code=.*|build/version_code=$CODE|" "$PROJECT"
else sed -i "s|^\[xiuxian\]$|[xiuxian]\n\nbuild/version_code=$CODE|" "$PROJECT"; fi

# ---------------------------------------------------------------- 3. 导出
mkdir -p "$GODOT_HOME/.local/share/godot/export_templates" "$OUT_DIR"
TPL="$GODOT_HOME/.local/share/godot/export_templates/4.7.2.stable"
[ -e "$TPL" ] || ln -s "$TOOLCHAIN/tpl/templates" "$TPL"
SETTINGS_DIR="$GODOT_HOME/.config/godot"
mkdir -p "$SETTINGS_DIR"
cat >"$SETTINGS_DIR/editor_settings-4.7.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$TOOLCHAIN/jdk"
export/android/android_sdk_path = "$TOOLCHAIN/sdk"
export/android/debug_keystore = "$TOOLCHAIN/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
TRES
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/game"
(cd "$ROOT/game" && tar --exclude=./.godot --exclude=./android/build --exclude=./tests --exclude='./addons/gut' -cf - .) | tar -xf - -C "$WORK/game"
sed -i "s|^network/api_base_url=.*|network/api_base_url=\"$APK_SERVER\"|" "$WORK/game/project.godot"
sed -i 's|"res://addons/gut/plugin.cfg", *||; s|, *"res://addons/gut/plugin.cfg"||' "$WORK/game/project.godot"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$WORK/game" --import >/dev/null 2>&1 || true
mkdir -p "$WORK/game/android/build"
unzip -q -o "$TPL/android_source.zip" -d "$WORK/game/android/build"
touch "$WORK/game/android/build/.gdignore"
echo "4.7.2.stable" >"$WORK/game/android/.build_version"
MANIFEST="$WORK/game/android/build/AndroidManifest.xml"
[ -f "$MANIFEST" ] || MANIFEST="$WORK/game/android/build/src/main/AndroidManifest.xml"
# 现在服务器只有 IP + http，必须允许明文；以后上 https 去掉这一行
sed -i 's|<application|<application android:usesCleartextTraffic="true"|' "$MANIFEST"
FILE="xiuxian-dev2-$VNAME-$CODE.apk"
APK="$OUT_DIR/$FILE"
say "导出 $FILE（gradle，第一次要下载依赖，几分钟）…"
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE" GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KEY_ALIAS" \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$KEYSTORE.pass")" GRADLE_USER_HOME="$GODOT_HOME/.gradle" HOME="$GODOT_HOME" \
  "$GODOT" --headless --path "$WORK/game" --export-release Android "$APK" >"$OUT_DIR/export-$CODE.log" 2>&1 || true
[ -s "$APK" ] || { tail -40 "$OUT_DIR/export-$CODE.log"; oops "导出失败，日志 $OUT_DIR/export-$CODE.log"; }

# ---------------------------------------------------------------- 4. 校验
"$BUILD_TOOLS/apksigner" verify --print-certs "$APK" >"$OUT_DIR/verify-$CODE.txt"
GOT_SHA="$(awk -F': ' '/certificate SHA-256 digest/ {print $2; exit}' "$OUT_DIR/verify-$CODE.txt" | tr -d ':' | tr 'a-f' 'A-F')"
[ "$GOT_SHA" = "$(echo "$CERT_SHA" | tr -d ':')" ] || oops "安装包的签名证书和固定密钥对不上（$GOT_SHA）"
# head 提前关管道会让 aapt2 收到 SIGPIPE，pipefail 下整句失败、set -e 直接无声退出 → 先完整输出再取
BADGING="$("$BUILD_TOOLS/aapt2" dump badging "$APK" 2>/dev/null || true)"
BADGING="$(printf '%s\n' "$BADGING" | sed -n '1,3p')"
grep -q "name='$PACKAGE_ID' versionCode='$CODE' versionName='$VNAME'" <<<"$BADGING" || oops "包名 / 版本不对：$BADGING"
SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
SIZE="$(stat -c %s "$APK")"
STAGE="$OUT_DIR/publish-$CODE"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$APK" "$STAGE/"
NOTES="${NOTES:-dev2 测试版 $VNAME}" PKG="$PACKAGE_ID" node -e '
  const [code, name, url, sha, size, force] = process.argv.slice(1);
  process.stdout.write(JSON.stringify({ versionCode: Number(code), versionName: name, url, sha256: sha, size: Number(size),
    notes: process.env.NOTES, force: force === "true", packageId: process.env.PKG, publishedAt: new Date().toISOString() }, null, 2) + "\n");
' "$CODE" "$VNAME" "$PUBLIC_URL/download/$FILE" "$SHA" "$SIZE" "$FORCE" >"$STAGE/latest.json"
say "签名 OK（证书 SHA-256 ${CERT_SHA:0:23}…），$((SIZE / 1048576)) MB，sha256 ${SHA:0:12}…"
if [ "$UPLOAD" = "1" ]; then
  "$HERE/deploy.sh" publish-apk "$STAGE"
  say "已发布：$PUBLIC_URL/download/latest.json"
else
  say "没有上传（--no-upload）：$STAGE"
fi
say "别忘了提交版本号改动：git add game/export_presets.cfg game/project.godot && git commit -m \"release: $VNAME ($CODE)\""
