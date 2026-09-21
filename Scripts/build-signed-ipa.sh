#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

archive="$PWD/build/Clipity-signed.xcarchive"
mkdir -p "$PWD/build"
staging="$(mktemp -d "$PWD/build/signed-ipa.XXXXXX")"
output="$PWD/Clipity-signed.ipa"
trap 'rm -rf "$staging"' EXIT

xcodebuild -project Clipity.xcodeproj -scheme Clipity -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  -allowProvisioningUpdates archive

mkdir -p "$staging/Payload"
ditto "$archive/Products/Applications/Clipity.app" "$staging/Payload/Clipity.app"
codesign --verify --deep --strict "$staging/Payload/Clipity.app"
ditto -c -k --keepParent "$staging/Payload" "$staging/Clipity-signed.ipa"
mv "$staging/Clipity-signed.ipa" "$output"
unzip -tq "$output"
printf 'Signed IPA: %s\n' "$output"
