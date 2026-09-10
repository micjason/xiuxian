#!/bin/sh
set -eu

# Drive the 0.1.4 first loop on desktop: offline dialog, three breakthroughs, journal.
# Does not rebuild, upload, or clobber a Release.

GODOT="${GODOT:-/Volumes/kaixia/GodotDev/bin/godot}"
GAME="/Volumes/kaixia/projects/xiuxian/game"
OUTDIR="/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4"

mkdir -p "$OUTDIR"
"$GODOT" --headless --path "$GAME" --import --quit-after 2 >/dev/null

set +e
"$GODOT" --path "$GAME" --display-driver macos --window-size 540x960 \
	-s res://scripts/dev/playthrough_014.gd
code=$?
set -e
if [ "$code" -ne 0 ]; then
	echo "Windowed playthrough failed (exit $code); trying headless logic capture." >&2
	"$GODOT" --headless --path "$GAME" -s res://scripts/dev/playthrough_014.gd
fi

REPORT="$OUTDIR/playthrough_014.json"
if [ ! -f "$REPORT" ]; then
	echo "Missing $REPORT" >&2
	exit 1
fi
python3 - "$REPORT" <<'PY'
import json, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
if not report.get("ok"):
    raise SystemExit(report.get("error") or "playthrough failed")
print("desktop first-loop ok realm=%s steps=%s" % (
    report.get("realm"),
    ",".join(step.get("realm", "") for step in report.get("steps", [])),
))
PY

SWIFT="/Volumes/kaixia/projects/xiuxian/tools/release/ocr_screenshot.swift"
ocr_png() {
	src="$1"
	dst="${src%.png}.ocr.txt"
	/usr/bin/swift "$SWIFT" "$src" > "$dst"
	echo "$dst"
}

has_any() {
	txt="$1"
	shift
	/usr/bin/python3 - "$txt" "$@" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
compact = "".join(text.split()).replace("\u3000", "")
for needle in sys.argv[2:]:
    if needle in text or "".join(needle.split()).replace("\u3000", "") in compact:
        print("ocr contains %s" % needle)
        raise SystemExit(0)
print("OCR missing any of %s" % " / ".join(sys.argv[2:]), file=sys.stderr)
print(text[:800], file=sys.stderr)
raise SystemExit(1)
PY
}

has_all() {
	txt="$1"
	shift
	/usr/bin/python3 - "$txt" "$@" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
compact = "".join(text.split()).replace("\u3000", "")
missing = []
for needle in sys.argv[2:]:
    if needle in text or "".join(needle.split()).replace("\u3000", "") in compact:
        print("ocr contains %s" % needle)
    else:
        missing.append(needle)
if missing:
    print("OCR missing %s" % " / ".join(missing), file=sys.stderr)
    print(text[:800], file=sys.stderr)
    raise SystemExit(1)
PY
}

OFFLINE_OCR=$(ocr_png "$OUTDIR/offline_dialog.png")
JOURNAL_OCR=$(ocr_png "$OUTDIR/breakthrough_journal.png")
has_any "$OFFLINE_OCR" "闭关" "归来" "获得修为" "结算时长" "精进"
has_all "$JOURNAL_OCR" "简记" "突破成功" "突破成功 炼气中期"
echo "desktop 0.1.4 screenshots match the same OCR gates as the phone playthrough."
