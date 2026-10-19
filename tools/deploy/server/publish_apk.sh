#!/usr/bin/env bash
# 发布一个安装包：校验后放进 /opt/$APP_NAME/shared/download/，最后原子地替换 latest.json（客户端看到的就是它）。
# 用法：publish_apk.sh <上传目录>   目录里有 *.apk 和 latest.json（release_apk.sh 生成）。只保留最近 3 个安装包。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
[ $# -ge 1 ] || die "用法：publish_apk.sh <上传目录>"
IN="$(cd "$1" && pwd)"
need_root
JSON="$IN/latest.json"
[ -f "$JSON" ] || die "没有 latest.json"
NODE_BIN="$(env_get "$ENV_FILE" NODE_BIN)"
NODE_BIN="${NODE_BIN:-/usr/local/bin/node}"
# 用 node 读 JSON（服务器上不一定有 jq）
read -r FILE SHA SIZE CODE NAME < <("$NODE_BIN" -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const f = decodeURIComponent(new URL(j.url).pathname.split("/").pop());
  if (!/^[A-Za-z0-9._-]+\.apk$/.test(f)) throw new Error("bad file name " + f);
  console.log(f, j.sha256, j.size, j.versionCode, j.versionName);' "$JSON")
APK="$IN/$FILE"
[ -f "$APK" ] || die "latest.json 指向 $FILE，但上传目录里没有它。"
[ "$(sha256sum "$APK" | cut -d' ' -f1)" = "$SHA" ] || die "$FILE 的 sha256 和 latest.json 不一致。"
[ "$(stat -c %s "$APK")" = "$SIZE" ] || die "$FILE 的大小和 latest.json 不一致。"
OLD_CODE="$( [ -f "$DOWNLOAD_DIR/latest.json" ] && "$NODE_BIN" -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).versionCode)' "$DOWNLOAD_DIR/latest.json" || echo 0)"
[ "$CODE" -gt "$OLD_CODE" ] || [ "${ALLOW_SAME_CODE:-0}" = "1" ] || die "versionCode $CODE 不高于线上的 $OLD_CODE，手机不会覆盖安装。"
install -m 0644 "$APK" "$DOWNLOAD_DIR/$FILE.part"
mv -f "$DOWNLOAD_DIR/$FILE.part" "$DOWNLOAD_DIR/$FILE"
install -m 0644 "$JSON" "$DOWNLOAD_DIR/latest.json.part"
mv -f "$DOWNLOAD_DIR/latest.json.part" "$DOWNLOAD_DIR/latest.json"
# shellcheck disable=SC2012
ls -1t "$DOWNLOAD_DIR"/*.apk 2>/dev/null | tail -n +4 | while IFS= read -r old; do rm -f "$old"; done
rm -rf "$IN"
log "已发布 $NAME（versionCode $CODE）：$FILE，$((SIZE / 1024 / 1024)) MB。线上 latest.json："
cat "$DOWNLOAD_DIR/latest.json"
echo
