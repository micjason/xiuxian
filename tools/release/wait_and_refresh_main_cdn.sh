#!/bin/sh
set -eu

# Wait out jsDelivr throttle, then refresh @main until it matches GitHub main
# and the APK is downloadable. Never uploads or clobbers a Release.

REFRESH="/Volumes/kaixia/projects/xiuxian/tools/release/refresh_main_cdn.sh"
UNTIL_EPOCH="${1:-}"
MAX_TRIES="${2:-8}"

if [ -n "$UNTIL_EPOCH" ]; then
	now="$(date +%s)"
	wait="$((UNTIL_EPOCH - now))"
	if [ "$wait" -gt 0 ]; then
		echo "Waiting ${wait}s for jsDelivr throttle to clear…"
		sleep "$wait"
	fi
fi

try=1
while [ "$try" -le "$MAX_TRIES" ]; do
	echo "==== refresh attempt $try/$MAX_TRIES ===="
	set +e
	out="$("$REFRESH" 2>&1)"
	code=$?
	set -e
	printf '%s\n' "$out"
	if [ "$code" -eq 0 ] && printf '%s\n' "$out" | grep -q "jsdelivr-main matches github-main"; then
		echo "jsDelivr @main now matches GitHub main and the APK is downloadable."
		exit 0
	fi
	if printf '%s\n' "$out" | grep -q "throttled=true"; then
		reset="$(printf '%s\n' "$out" | awk -F= '/throttled=true/ {print $3; exit}')"
		reset="${reset:-600}"
		echo "Still throttled. Sleeping ${reset}s + 30s buffer…"
		sleep "$((reset + 30))"
	else
		echo "Cache still stale or APK not downloadable. Sleeping 600s…"
		sleep 600
	fi
	try="$((try + 1))"
done

echo "jsDelivr @main is still not serving the live APK." >&2
exit 1
