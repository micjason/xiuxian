#!/bin/sh
set -eu

# On an unlocked phone already running 0.1.4: settle offline, then optionally
# clear data and walk the first three realms. Does not rebuild or clobber.

ADB="/Volumes/kaixia/GodotDev/xiuxian/android/sdk/platform-tools/adb"
PKG="com.micjason.xiuxian"
ACTIVITY="com.godot.game.GodotApp"
OUTDIR="/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4"
CLEAR="${CLEAR:-0}"
REPORT="/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/playthrough_014.json"

if ! "$ADB" devices | /usr/bin/awk 'NR>1 && $2=="device" {found=1} END {exit found?0:1}'; then
	echo "No authorized Android device on this project's adb." >&2
	"$ADB" devices -l
	exit 1
fi

mkdir -p "$OUTDIR"

shot() {
	name="$1"
	path="$OUTDIR/$name"
	"$ADB" exec-out screencap -p > "$path"
	size=$(/usr/bin/stat -f%z "$path")
	echo "screenshot=$path size=$size"
	if [ "$size" -lt 10000 ]; then
		echo "Screenshot looks empty; unlock the phone and run this script again." >&2
		exit 2
	fi
}

map_tap() {
	# Map a 1080x1920 point onto the device framebuffer, keeping aspect.
	vx="$1"
	vy="$2"
	size="$("$ADB" shell wm size | /usr/bin/tr -d '\r')"
	dw=$(printf '%s\n' "$size" | /usr/bin/sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1/p' | /usr/bin/tail -1)
	dh=$(printf '%s\n' "$size" | /usr/bin/sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\2/p' | /usr/bin/tail -1)
	python3 - "$dw" "$dh" "$vx" "$vy" <<'PY'
import sys
dw, dh, vx, vy = (float(x) for x in sys.argv[1:])
scale = min(dw / 1080.0, dh / 1920.0)
ox = (dw - 1080.0 * scale) / 2.0
oy = (dh - 1920.0 * scale) / 2.0
print("%d %d" % (round(ox + vx * scale), round(oy + vy * scale)))
PY
}

tap_viewport() {
	point=$(map_tap "$1" "$2")
	echo "tap viewport=($1,$2) device=($point)"
	"$ADB" shell input tap $point
}

button_center() {
	if [ -f "$REPORT" ]; then
		python3 - "$REPORT" <<'PY'
import json, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
rect = report.get("button_rect") or []
if len(rect) != 4:
    print("540 1020")
else:
    print("%d %d" % (round(rect[0] + rect[2] / 2.0), round(rect[1] + rect[3] / 2.0)))
PY
	else
		echo "540 1020"
	fi
}

wake() {
	"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
	"$ADB" shell input keyevent KEYCODE_MENU >/dev/null 2>&1 || true
	# Swipe-up lock screens only; PIN/pattern still needs a person.
	"$ADB" shell input swipe 540 2000 540 700 220 >/dev/null 2>&1 || true
}

wait_game() {
	i=0
	while [ "$i" -lt 25 ]; do
		if "$ADB" shell pidof "$PKG" >/dev/null 2>&1; then
			sleep 8
			return 0
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "Game process did not start." >&2
	return 1
}

start_game() {
	wake
	"$ADB" shell am start -n "$PKG/$ACTIVITY" >/dev/null
	wait_game
}

wake

if [ "$CLEAR" = "1" ]; then
	echo "Clearing app data for a clean first-three-realms run."
	"$ADB" shell pm clear "$PKG" >/dev/null
fi

"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
start_game
shot "device_launch.png"

# Leave long enough for one online tick, then reopen to force offline settlement.
sleep 3
"$ADB" shell am force-stop "$PKG" >/dev/null
sleep 8
start_game
shot "device_offline.png"

# Dismiss the 闭关 dialog if it is up.
"$ADB" shell input keyevent KEYCODE_ENTER >/dev/null 2>&1 || true
sleep 1
tap_viewport 540 1140
sleep 1
shot "device_after_offline.png"

if [ "$CLEAR" != "1" ]; then
	echo "Offline reopen captured. Set CLEAR=1 to also walk the first three realms."
	"$ADB" logcat -d -t 120 *:S godot:I Godot:I xiuxian:I \
		> "$OUTDIR/device_playthrough_logcat.txt" 2>/dev/null || true
	echo "device offline check finished."
	exit 0
fi

center=$(button_center)
bx=$(printf '%s' "$center" | /usr/bin/awk '{print $1}')
by=$(printf '%s' "$center" | /usr/bin/awk '{print $2}')
i=1
for wait in 10 21 31; do
	echo "waiting ${wait}s for breakthrough $i"
	sleep "$wait"
	tap_viewport "$bx" "$by"
	sleep 1
	shot "device_breakthrough_$i.png"
	i=$((i + 1))
done
shot "device_journal.png"
"$ADB" logcat -d -t 200 *:S godot:I Godot:I xiuxian:I \
	> "$OUTDIR/device_playthrough_logcat.txt" 2>/dev/null || true
python3 - "$OUTDIR" <<'PY'
import json, os, sys, time
out = sys.argv[1]
shots = [
    "device_launch.png",
    "device_offline.png",
    "device_after_offline.png",
    "device_breakthrough_1.png",
    "device_breakthrough_2.png",
    "device_breakthrough_3.png",
    "device_journal.png",
]
report = {
    "ok": True,
    "cleared": os.environ.get("CLEAR", "0") == "1",
    "finished_unix": int(time.time()),
    "screenshots": {
        name: os.path.getsize(os.path.join(out, name))
        for name in shots
        if os.path.isfile(os.path.join(out, name))
    },
}
open(os.path.join(out, "device_playthrough.json"), "w", encoding="utf-8").write(
    json.dumps(report, ensure_ascii=False, indent=2)
)
print("wrote %s/device_playthrough.json shots=%s" % (out, ",".join(report["screenshots"])))
PY
echo "device first-loop playthrough finished."
