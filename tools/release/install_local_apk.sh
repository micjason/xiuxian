#!/bin/sh
set -eu

APK="${1:-/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/xiuxian.apk}"
ADB="/Volumes/kaixia/GodotDev/xiuxian/android/sdk/platform-tools/adb"
AAPT="/Volumes/kaixia/GodotDev/xiuxian/android/sdk/build-tools/35.0.1/aapt2"

if [ ! -f "$APK" ]; then
	echo "APK not found: $APK" >&2
	exit 1
fi

ACTUAL_SHA=$(/usr/bin/shasum -a 256 "$APK" | /usr/bin/awk '{print $1}')
EXPECTED_JSON="${TMPDIR:-/tmp}/xiuxian-install-expected.json"
/usr/bin/curl -fsS -A "XiuxianUpdater/0.1" \
	https://raw.githubusercontent.com/micjason/xiuxian-releases/main/update.json \
	-o "$EXPECTED_JSON"
EXPECTED_SHA=$(/usr/bin/python3 -c "import json; print(json.load(open('$EXPECTED_JSON'))['apk_sha256'])")
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
	echo "Local APK does not match the live 0.1.4 channel." >&2
	echo "local  $ACTUAL_SHA" >&2
	echo "live   $EXPECTED_SHA" >&2
	exit 1
fi
echo "apk matches live channel sha=$(printf '%s' "$ACTUAL_SHA" | /usr/bin/cut -c1-16)"

if ! "$ADB" devices | /usr/bin/awk 'NR>1 && $2=="device" {found=1} END {exit found?0:1}'; then
	echo "No authorized Android device on this project's adb." >&2
	"$ADB" devices -l
	exit 1
fi

"$AAPT" dump badging "$APK" | /usr/bin/egrep 'package:|application-label:'
if "$AAPT" dump badging "$APK" | /usr/bin/grep -q 'CATEGORY_HOME'; then
	echo "Refusing to install a launcher APK." >&2
	exit 1
fi
"$ADB" shell am force-stop com.micjason.xiuxian >/dev/null 2>&1 || true
"$ADB" install -r "$APK"
"$ADB" shell dumpsys package com.micjason.xiuxian | /usr/bin/egrep 'versionName=|versionCode='
