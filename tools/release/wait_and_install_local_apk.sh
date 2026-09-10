#!/bin/sh
set -eu

# Wait for the project adb device, then install the live 0.1.4 APK.
# Does not rebuild, upload, or clobber a Release.

INTERVAL="${1:-10}"
INSTALL="/Volumes/kaixia/projects/xiuxian/tools/release/install_local_apk.sh"
ADB="/Volumes/kaixia/GodotDev/xiuxian/android/sdk/platform-tools/adb"

echo "Waiting for an authorized Android device…"
while :; do
	if "$ADB" devices 2>/dev/null | /usr/bin/awk 'NR>1 && $2=="device" {found=1} END {if (found) exit 0; exit 1}'; then
		break
	fi
	sleep "$INTERVAL"
done

"$INSTALL"
echo "Installed live 0.1.4."

VERIFY="/Volumes/kaixia/projects/xiuxian/tools/release/verify_device_014.sh"
PLAY="/Volumes/kaixia/projects/xiuxian/tools/release/verify_device_playthrough_014.sh"
# A locked phone can still install. Keep retrying screenshots until it is
# unlocked; a lock-screen PNG is large enough to fake a "passed" shot.
while :; do
	set +e
	"$VERIFY"
	verify_code=$?
	set -e
	if [ "$verify_code" -eq 0 ]; then
		echo "On-device 0.1.4 version check passed."
		set +e
		# Home screenshot already captured the kept save. Clear, then walk
		# offline + the first three realms on a fresh 0.1.4 loop.
		CLEAR="${CLEAR:-1}" "$PLAY"
		play_code=$?
		set -e
		if [ "$play_code" -eq 0 ]; then
			echo "On-device 0.1.4 playthrough passed."
			"$ADB" shell svc power stayon false >/dev/null 2>&1 || true
			exit 0
		elif [ "$play_code" -eq 2 ]; then
			echo "Package is 0.1.4; waiting for the phone to be unlocked…"
			sleep "$INTERVAL"
			continue
		else
			echo "On-device playthrough failed (exit $play_code)." >&2
			exit "$play_code"
		fi
	elif [ "$verify_code" -eq 2 ]; then
		echo "Package is 0.1.4; waiting for the phone to be unlocked…"
		sleep "$INTERVAL"
	else
		echo "On-device check failed (exit $verify_code)." >&2
		exit "$verify_code"
	fi
done
