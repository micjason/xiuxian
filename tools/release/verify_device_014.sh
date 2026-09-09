#!/bin/sh
set -eu

# After 0.1.4 is on the phone: check version, launch, screenshot.
# Does not rebuild, upload, or clobber a Release.

ADB="/Volumes/kaixia/GodotDev/xiuxian/android/sdk/platform-tools/adb"
PKG="com.micjason.xiuxian"
ACTIVITY="com.godot.game.GodotApp"
OUTDIR="/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4"
SHOT="$OUTDIR/device_home.png"

if ! "$ADB" devices | /usr/bin/awk 'NR>1 && $2=="device" {found=1} END {exit found?0:1}'; then
	echo "No authorized Android device on this project's adb." >&2
	"$ADB" devices -l
	exit 1
fi

DUMP="$("$ADB" shell dumpsys package "$PKG")"
echo "$DUMP" | /usr/bin/egrep 'versionName=|versionCode=' | /usr/bin/head -8
if ! printf '%s\n' "$DUMP" | /usr/bin/grep -q 'versionName=0.1.4'; then
	echo "Installed package is not 0.1.4." >&2
	exit 1
fi
if ! printf '%s\n' "$DUMP" | /usr/bin/grep -q 'versionCode=5'; then
	echo "Installed versionCode is not 5." >&2
	exit 1
fi
if printf '%s\n' "$DUMP" | /usr/bin/grep -q 'CATEGORY_HOME'; then
	echo "Installed package still claims CATEGORY_HOME." >&2
	exit 1
fi

mkdir -p "$OUTDIR"
"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
"$ADB" shell am start -n "$PKG/$ACTIVITY" >/dev/null
sleep 5
"$ADB" exec-out screencap -p > "$SHOT"

SIZE=$(/usr/bin/stat -f%z "$SHOT")
echo "screenshot=$SHOT size=$SIZE"
if [ "$SIZE" -lt 10000 ]; then
	echo "Screenshot looks empty; unlock the phone and run this script again." >&2
	exit 2
fi

UIXML="${TMPDIR:-/tmp}/xiuxian-device-ui.xml"
if "$ADB" shell uiautomator dump /data/local/tmp/xiuxian-ui.xml >/dev/null 2>&1; then
	"$ADB" pull /data/local/tmp/xiuxian-ui.xml "$UIXML" >/dev/null
	if /usr/bin/grep -q '修仙\|突破\|凡人\|简记\|离线' "$UIXML"; then
		echo "ui dump contains first-loop copy"
	else
		echo "ui dump has no readable game text (common for Godot); use the screenshot"
	fi
fi

echo "device 0.1.4 version and screenshot are ready."
echo "Next: tools/release/verify_device_playthrough_014.sh (offline reopen; CLEAR=1 also walks the first three realms)."
