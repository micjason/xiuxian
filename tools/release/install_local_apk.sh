#!/bin/sh
set -eu

APK="${1:-/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/xiuxian.apk}"
ADB="/Volumes/kaixia/GodotDev/xiuxian/android/sdk/platform-tools/adb"
AAPT="/Volumes/kaixia/GodotDev/xiuxian/android/sdk/build-tools/35.0.1/aapt2"

if [ ! -f "$APK" ]; then
	echo "APK not found: $APK" >&2
	exit 1
fi

if ! "$ADB" devices | /usr/bin/awk 'NR>1 && $2=="device" {found=1} END {exit found?0:1}'; then
	echo "No authorized Android device on this project's adb." >&2
	"$ADB" devices -l
	exit 1
fi

"$AAPT" dump badging "$APK" | /usr/bin/egrep 'package:|application-label:'
"$ADB" install -r "$APK"
"$ADB" shell dumpsys package com.micjason.xiuxian | /usr/bin/egrep 'versionName=|versionCode='
