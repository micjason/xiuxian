#!/bin/sh
set -eu

# Write a checksum-valid 9-hour offline save and push it onto the phone.
# Release APKs are usually not debuggable; if every path fails, the caller
# should fall back to a short force-stop settlement.

ADB="${ADB:-/Volumes/kaixia/GodotDev/xiuxian/android/sdk/platform-tools/adb}"
GODOT="${GODOT:-/Volumes/kaixia/GodotDev/bin/godot}"
GAME="${GAME:-/Volumes/kaixia/projects/xiuxian/game}"
PKG="${PKG:-com.micjason.xiuxian}"
SEED="${SEED:-/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/seed_cultivation.json}"

if ! "$ADB" devices | /usr/bin/awk 'NR>1 && $2=="device" {found=1} END {exit found?0:1}'; then
	echo "No authorized Android device on this project's adb." >&2
	exit 1
fi

"$GODOT" --headless --path "$GAME" -s res://scripts/dev/write_capped_offline_save.gd
if [ ! -f "$SEED" ]; then
	echo "Failed to write $SEED" >&2
	exit 1
fi

"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true

# Shared/scoped storage first; private app files via run-as if the build allows it.
for dest in \
	"/sdcard/Android/data/$PKG/files/saves/cultivation.json" \
	"/storage/emulated/0/Android/data/$PKG/files/saves/cultivation.json"
do
	dir=$(printf '%s' "$dest" | /usr/bin/sed 's:/[^/]*$::')
	if "$ADB" shell mkdir -p "$dir" >/dev/null 2>&1 \
		&& "$ADB" push "$SEED" "$dest" >/dev/null; then
		echo "pushed capped offline save to $dest"
		exit 0
	fi
done

"$ADB" push "$SEED" /data/local/tmp/xiuxian_cultivation.json >/dev/null
if "$ADB" shell run-as "$PKG" sh -c 'mkdir -p files/saves && cp /data/local/tmp/xiuxian_cultivation.json files/saves/cultivation.json' >/dev/null 2>&1; then
	echo "pushed capped offline save via run-as files/saves"
	exit 0
fi

echo "Could not write the app save directory; use a short offline wait instead." >&2
exit 2
