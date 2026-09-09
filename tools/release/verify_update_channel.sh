#!/bin/sh
set -eu

REF="${1:-latest}"
PUBKEY="${2:-/Volumes/kaixia/GodotDev/xiuxian/signing/update-public.pem}"
WORKDIR="${TMPDIR:-/tmp}/xiuxian-update-verify-$REF"
MANIFEST_URL="https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@${REF}/update.json"
SIGNATURE_URL="https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@${REF}/update.sig"

mkdir -p "$WORKDIR"
/usr/bin/curl -fsS -A "XiuxianUpdater/0.1" -H "Cache-Control: no-cache" "$MANIFEST_URL" -o "$WORKDIR/update.json"
/usr/bin/curl -fsS -A "XiuxianUpdater/0.1" -H "Cache-Control: no-cache" "$SIGNATURE_URL" -o "$WORKDIR/update.sig"
/usr/bin/openssl dgst -sha256 -verify "$PUBKEY" -signature "$WORKDIR/update.sig" "$WORKDIR/update.json"

APK_URL=$(/usr/bin/python3 -c "import json; print(json.load(open('$WORKDIR/update.json'))['apk_url'])")
APK_SIZE=$(/usr/bin/python3 -c "import json; print(json.load(open('$WORKDIR/update.json'))['apk_size'])")
APK_SHA=$(/usr/bin/python3 -c "import json; print(json.load(open('$WORKDIR/update.json'))['apk_sha256'])")
VERSION=$(/usr/bin/python3 -c "import json; print(json.load(open('$WORKDIR/update.json'))['version'])")

/usr/bin/curl -fL --retry 2 \
	-A "XiuxianUpdater/0.1" \
	-H "Accept: application/octet-stream" \
	"$APK_URL" -o "$WORKDIR/xiuxian.apk"

ACTUAL_SIZE=$(/usr/bin/stat -f%z "$WORKDIR/xiuxian.apk")
ACTUAL_SHA=$(/usr/bin/shasum -a 256 "$WORKDIR/xiuxian.apk" | /usr/bin/awk '{print $1}')
if [ "$ACTUAL_SIZE" != "$APK_SIZE" ] || [ "$ACTUAL_SHA" != "$APK_SHA" ]; then
	echo "APK mismatch for $REF version=$VERSION" >&2
	echo "expected size=$APK_SIZE sha=$APK_SHA" >&2
	echo "actual   size=$ACTUAL_SIZE sha=$ACTUAL_SHA" >&2
	exit 1
fi

echo "OK $REF version=$VERSION size=$ACTUAL_SIZE sha=${ACTUAL_SHA}"
