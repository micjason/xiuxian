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
