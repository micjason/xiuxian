#!/bin/sh
set -eu

# Wait for the project adb device, then install the live 0.1.4 APK.
# Does not rebuild, upload, or clobber a Release.

INTERVAL="${1:-10}"
INSTALL="/Volumes/kaixia/projects/xiuxian/tools/release/install_local_apk.sh"
ADB="/Volumes/kaixia/GodotDev/xiuxian/android/sdk/platform-tools/adb"

echo "Waiting for an authorized Android device…"
while ! "$ADB" devices | /usr/bin/awk 'NR>1 && $2=="device" {found=1} END {exit found?0:1}'; do
	sleep "$INTERVAL"
done

"$INSTALL"
echo "Installed live 0.1.4."
