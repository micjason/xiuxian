#!/bin/sh
set -eu

VERSION="${1:?usage: build_android.sh VERSION OUTPUT_APK}"
OUTPUT_APK="${2:?usage: build_android.sh VERSION OUTPUT_APK}"

PROJECT_ROOT="/Volumes/kaixia/projects/xiuxian"
TOOL_ROOT="/Volumes/kaixia/GodotDev/xiuxian"
GODOT="/Volumes/kaixia/GodotDev/bin/godot"
KEYSTORE="$TOOL_ROOT/signing/xiuxian-release.keystore"

PROJECT_VERSION=$(/usr/bin/awk -F'=' '/^config\/version=/{gsub(/"/, "", $2); print $2}' "$PROJECT_ROOT/game/project.godot")
if [ "$PROJECT_VERSION" != "$VERSION" ]; then
	echo "Project version is $PROJECT_VERSION, expected $VERSION." >&2
	exit 1
fi

PASSWORD=$(/usr/bin/security find-generic-password \
	-a xiuxian \
	-s com.micjason.xiuxian.release \
	-w)

export JAVA_HOME="$TOOL_ROOT/android/jdk/Contents/Home"
export ANDROID_HOME="$TOOL_ROOT/android/sdk"
export ANDROID_SDK_ROOT="$TOOL_ROOT/android/sdk"
export ANDROID_USER_HOME="$TOOL_ROOT/android/cache"
export GRADLE_USER_HOME="$TOOL_ROOT/android/gradle-cache"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="xiuxian"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PASSWORD"

/bin/mkdir -p "$(/usr/bin/dirname "$OUTPUT_APK")"
"$GODOT" \
	--headless \
	--path "$PROJECT_ROOT/game" \
	--install-android-build-template \
	--export-release Android \
	"$OUTPUT_APK"
