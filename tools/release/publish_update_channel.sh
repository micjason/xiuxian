#!/bin/sh
set -eu

# Publish signed channel files for a NEW GitHub Release.
# Never clobbers an existing xiuxian.apk; that can leave @main on a deleted asset.

VERSION="${1:?usage: publish_update_channel.sh VERSION VERSION_CODE CHANNEL_TAG NOTES APK}"
VERSION_CODE="${2:?usage: publish_update_channel.sh VERSION VERSION_CODE CHANNEL_TAG NOTES APK}"
CHANNEL_TAG="${3:?usage: publish_update_channel.sh VERSION VERSION_CODE CHANNEL_TAG NOTES APK}"
NOTES="${4:?usage: publish_update_channel.sh VERSION VERSION_CODE CHANNEL_TAG NOTES APK}"
APK="${5:?usage: publish_update_channel.sh VERSION VERSION_CODE CHANNEL_TAG NOTES APK}"

ROOT="/Volumes/kaixia/projects/xiuxian"
GH="/Volumes/kaixia/GodotDev/xiuxian/bin/gh"
REPO="/Volumes/kaixia/GodotDev/xiuxian/release-repo"
ASSETS="$ROOT/builds/development/$VERSION/release-assets"
CHECK="$ROOT/tools/release/check_update_channel.sh"

if [ ! -f "$APK" ]; then
	echo "APK not found: $APK" >&2
	exit 1
fi

if ! "$CHECK"; then
	echo "A live update channel is broken. Fix @main before publishing another APK." >&2
	echo "USB fallback: adb install -r $APK" >&2
	exit 1
fi

if git -C "$REPO" rev-parse "$CHANNEL_TAG" >/dev/null 2>&1; then
	echo "Channel tag already exists: $CHANNEL_TAG" >&2
	exit 1
fi

"$GH" release view "v$VERSION" --repo micjason/xiuxian-releases >/dev/null 2>&1 && {
	echo "GitHub release v$VERSION already exists. Do not clobber its APK." >&2
	exit 1
}

mkdir -p "$ASSETS"
"$GH" release create "v$VERSION" "$APK#xiuxian.apk" \
	--repo micjason/xiuxian-releases \
	--title "v$VERSION" \
	--notes "$NOTES"

ASSET_ID=$("$GH" api "repos/micjason/xiuxian-releases/releases/tags/v$VERSION" --jq '.assets[] | select(.name=="xiuxian.apk") | .id')
python3 "$ROOT/tools/release/create_update_manifest.py" \
	--apk "$APK" \
	--version "$VERSION" \
	--version-code "$VERSION_CODE" \
	--apk-url "https://api.github.com/repos/micjason/xiuxian-releases/releases/assets/${ASSET_ID}" \
	--release-notes "$NOTES" \
	--private-key /Volumes/kaixia/GodotDev/xiuxian/signing/update-private.pem \
	--output-directory "$ASSETS"

/usr/bin/openssl dgst -sha256 \
	-verify /Volumes/kaixia/GodotDev/xiuxian/signing/update-public.pem \
	-signature "$ASSETS/update.sig" \
	"$ASSETS/update.json"

"$GH" release upload "v$VERSION" "$ASSETS/update.json" "$ASSETS/update.sig" \
	--repo micjason/xiuxian-releases

cp "$ASSETS/update.json" "$REPO/update.json"
cp "$ASSETS/update.sig" "$REPO/update.sig"
git -C "$REPO" add update.json update.sig
git -C "$REPO" commit -m "Publish $VERSION channel files for $CHANNEL_TAG."
git -C "$REPO" tag "$CHANNEL_TAG"
git -C "$REPO" push origin main
git -C "$REPO" push origin "$CHANNEL_TAG"
echo "Published v$VERSION with channel $CHANNEL_TAG asset=$ASSET_ID"
