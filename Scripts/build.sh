#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
if ! xcodebuild -project Amethyst.xcodeproj -scheme Amethyst -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 build; then
    echo 'Amethyst device compilation failed. See Xcode diagnostics above.' >&2
    exit 1
fi
app=build/DerivedData/Build/Products/Release-iphoneos/Amethyst.app
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/Amethyst.app" || { echo 'Failed to stage application bundle.' >&2; exit 1; }
(cd "$stage" && /usr/bin/zip -qry Amethyst.ipa Payload) || { echo 'Failed to create IPA archive.' >&2; exit 1; }
python3 Scripts/validate.py "$stage/Amethyst.ipa"
mv "$stage/Amethyst.ipa" build/Amethyst.ipa
