#!/bin/sh
set -eu

# Refresh jsDelivr @main so 0.1.3 clients can download the live APK.
# Never uploads or clobbers a Release.

PUBKEY="${1:-/Volumes/kaixia/GodotDev/xiuxian/signing/update-public.pem}"
WORKDIR="${TMPDIR:-/tmp}/xiuxian-refresh-main"
mkdir -p "$WORKDIR"

purge_one() {
	path="$1"
	/usr/bin/curl -sS "https://purge.jsdelivr.net/gh/micjason/xiuxian-releases@${path}" \
		-o "$WORKDIR/purge-$(echo "$path" | tr '/@' '--').json"
}

purge_one "main/update.json"
purge_one "main/update.sig"

python3 - "$WORKDIR" <<'PY'
import json, pathlib, sys
work = pathlib.Path(sys.argv[1])
reset = 0
throttled = False
for name in work.glob("purge-*.json"):
    data = json.loads(name.read_text())
    paths = data.get("paths") or {}
    for info in paths.values():
        if info.get("throttled"):
            throttled = True
            reset = max(reset, int(info.get("throttlingReset") or 0))
if throttled:
    print(f"throttled=true reset={reset}")
    sys.exit(2)
print("throttled=false")
PY

sleep 2
exec /Volumes/kaixia/projects/xiuxian/tools/release/check_update_channel.sh "$PUBKEY"
