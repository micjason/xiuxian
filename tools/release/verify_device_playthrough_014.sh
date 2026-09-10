#!/bin/sh
set -eu

# On an unlocked phone already running 0.1.4: settle offline, then optionally
# clear data and walk the first three realms. Does not rebuild or clobber.

. /Volumes/kaixia/projects/xiuxian/tools/release/device_common.sh
OUTDIR="/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4"
CLEAR="${CLEAR:-0}"
REPORT="/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/playthrough_014.json"

require_adb_device || exit 1

mkdir -p "$OUTDIR"

shot() {
	name="$1"
	path="$OUTDIR/$name"
	require_unlocked_screen || exit $?
	"$ADB" exec-out screencap -p > "$path"
	size=$(/usr/bin/stat -f%z "$path")
	echo "screenshot=$path size=$size"
	if [ "$size" -lt 10000 ]; then
		echo "Screenshot looks empty; unlock the phone and run this script again." >&2
		exit 2
	fi
	require_game_screenshot "$path" || exit $?
}

map_tap() {
	# Map a 1080x1920 point onto the running game window, keeping aspect.
	vx="$1"
	vy="$2"
	rect=$(game_window_rect)
	/usr/bin/python3 - "$rect" "$vx" "$vy" <<'PY'
import sys
x, y, dw, dh = (float(v) for v in sys.argv[1].split())
vx, vy = (float(v) for v in sys.argv[2:])
scale = min(dw / 1080.0, dh / 1920.0)
ox = x + (dw - 1080.0 * scale) / 2.0
oy = y + (dh - 1920.0 * scale) / 2.0
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
		/usr/bin/python3 - "$REPORT" <<'PY'
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
	wake_device
	keep_screen_on
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
	launch_game
	wait_game
}

wake

if [ "$CLEAR" = "1" ]; then
	echo "Clearing app data for a clean first-three-realms run."
	APK="${APK:-/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/xiuxian.apk}"
	if ! "$ADB" shell pm clear "$PKG" >/dev/null 2>&1; then
		echo "pm clear blocked; uninstalling and reinstalling the live APK."
		"$ADB" uninstall "$PKG"
		"$ADB" install "$APK"
	fi
fi

"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
start_game
shot "device_launch.png"

# Prefer a checksum-valid 9-hour save so the 闭关 dialog shows the 8-hour cap.
# If the release package blocks writes, fall back to a short force-stop.
sleep 3
"$ADB" shell am force-stop "$PKG" >/dev/null
SEED_PUSH="/Volumes/kaixia/projects/xiuxian/tools/release/push_capped_offline_save.sh"
set +e
"$SEED_PUSH"
seed_code=$?
set -e
if [ "$seed_code" -ne 0 ]; then
	echo "Seeded save unavailable (exit $seed_code); waiting 12s for a short offline settlement."
	sleep 12
fi
start_game
shot "device_offline.png"
# 主界面路径里没有「闭关」。弹窗 OCR 偶发把「闭关归来」认成近形字，所以多给几个离线文案。
require_ocr_any "$OUTDIR/device_offline.png" "闭关" "归来" "获得修为" "结算时长" "精进" || exit 1

# Short offline is a toast, not a modal. ENTER is enough; do not tap the
# gold 突破境界 bar here or the 凡人 banner is gone before we screenshot it.
"$ADB" shell input keyevent KEYCODE_ENTER >/dev/null 2>&1 || true
sleep 1
shot "device_after_offline.png"

if [ "$CLEAR" != "1" ]; then
	echo "Offline reopen captured. Set CLEAR=1 to also walk the first three realms."
	"$ADB" logcat -d -t 120 *:S godot:I Godot:I xiuxian:I \
		> "$OUTDIR/device_playthrough_logcat.txt" 2>/dev/null || true
	restore_screen_timeout
	echo "device offline check finished."
	exit 0
fi

# 按钮「突破境界」和路径里的「炼气」一直在。横幅是「突破成功  凡人 → …」，
# 简记是「突破成功：凡人 → …」。必须对上横幅空格，不能拿简记里的冒号充数。
tap_until_banner() {
	index="$1"
	budget="$2"
	shift 2
	name="device_breakthrough_${index}.png"
	source="$OUTDIR/device_after_offline.png"
	if [ "$index" -gt 1 ]; then
		prev=$((index - 1))
		source="$OUTDIR/device_breakthrough_${prev}.png"
	fi
	elapsed=0
	echo "tapping for breakthrough $index (budget ${budget}s, $*)"
	while [ "$elapsed" -lt "$budget" ]; do
		tap_gold_button "$source"
		sleep 1
		shot "$name"
		source="$OUTDIR/$name"
		if require_ocr_any "$OUTDIR/$name" "$@"; then
			# 横幅约 3.6 秒后消失。等它灭掉，避免下一阶 OCR 吃到上一张残影。
			sleep 4
			return 0
		fi
		sleep 4
		elapsed=$((elapsed + 5))
	done
	echo "Did not see banner ($*) on $name" >&2
	return 1
}

tap_until_banner 1 25 "突破成功 凡人" "突破成功  凡人" || exit 1
tap_until_banner 2 35 "突破成功 炼气初期" "突破成功  炼气初期" || exit 1
tap_until_banner 3 45 "突破成功 炼气中期" "突破成功  炼气中期" || exit 1
shot "device_journal.png"
require_ocr_all "$OUTDIR/device_journal.png" "简记" "突破成功" || exit 1
"$ADB" logcat -d -t 200 *:S godot:I Godot:I xiuxian:I \
	> "$OUTDIR/device_playthrough_logcat.txt" 2>/dev/null || true
/usr/bin/python3 - "$OUTDIR" <<'PY'
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
ocr = {}
for name in shots:
    text_path = os.path.join(out, name.replace(".png", ".ocr.txt"))
    if os.path.isfile(text_path):
        ocr[name] = open(text_path, encoding="utf-8").read()
report = {
    "ok": True,
    "cleared": os.environ.get("CLEAR", "0") == "1",
    "finished_unix": int(time.time()),
    "screenshots": {
        name: os.path.getsize(os.path.join(out, name))
        for name in shots
        if os.path.isfile(os.path.join(out, name))
    },
    "ocr": ocr,
}
open(os.path.join(out, "device_playthrough.json"), "w", encoding="utf-8").write(
    json.dumps(report, ensure_ascii=False, indent=2)
)
print("wrote %s/device_playthrough.json shots=%s" % (out, ",".join(report["screenshots"])))
PY
restore_screen_timeout
echo "device first-loop playthrough finished."
