#!/bin/sh
set -eu

# Use Godot HTTPRequest (same stack as the phone updater) against the live channel.
# Does not rebuild, upload, or clobber a Release.

GODOT="${GODOT:-/Volumes/kaixia/GodotDev/bin/godot}"
GAME="${GAME:-/Volumes/kaixia/projects/xiuxian/game}"

"$GODOT" --headless --path "$GAME" -s res://scripts/dev/verify_live_update_path.gd
