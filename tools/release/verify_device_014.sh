#!/bin/sh
set -eu

# After 0.1.4 is on the phone: check version, launch, screenshot.
# Does not rebuild, upload, or clobber a Release.

. /Volumes/kaixia/projects/xiuxian/tools/release/device_common.sh
OUTDIR="/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4"
SHOT="$OUTDIR/device_home.png"

require_adb_device || exit 1

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
require_unlocked_screen || exit $?
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
launch_game
i=0
while [ "$i" -lt 20 ]; do
	if "$ADB" shell pidof "$PKG" >/dev/null 2>&1; then
		break
	fi
	sleep 1
	i=$((i + 1))
done
sleep 8
require_unlocked_screen || exit $?
"$ADB" exec-out screencap -p > "$SHOT"

SIZE=$(/usr/bin/stat -f%z "$SHOT")
echo "screenshot=$SHOT size=$SIZE"
if [ "$SIZE" -lt 10000 ]; then
	echo "Screenshot looks empty; unlock the phone and run this script again." >&2
	exit 2
fi
require_game_screenshot "$SHOT" || exit $?
require_ocr_any "$SHOT" "修仙" "修为" "凡人" "炼气" || exit 1

UIXML="${TMPDIR:-/tmp}/xiuxian-device-ui.xml"
if "$ADB" shell uiautomator dump /data/local/tmp/xiuxian-ui.xml >/dev/null 2>&1; then
	"$ADB" pull /data/local/tmp/xiuxian-ui.xml "$UIXML" >/dev/null
	if /usr/bin/grep -q '修仙\|突破\|凡人\|简记\|离线' "$UIXML"; then
		echo "ui dump contains first-loop copy"
	else
		echo "ui dump has no readable game text (common for Godot); use the screenshot"
	fi
fi

"$ADB" logcat -d -t 120 *:S godot:I Godot:I xiuxian:I \
	> "$OUTDIR/device_logcat.txt" 2>/dev/null || true
echo "device 0.1.4 version and screenshot are ready."
echo "Next: tools/release/verify_device_playthrough_014.sh (offline reopen; CLEAR=1 also walks the first three realms)."
