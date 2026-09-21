#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

archive="$PWD/build/Clipity.xcarchive"
mkdir -p "$PWD/build"
staging="$(mktemp -d "$PWD/build/unsigned-ipa.XXXXXX")"
output="$PWD/Clipity-unsigned.ipa"
trap 'rm -rf "$staging"' EXIT

xcodebuild -project Clipity.xcodeproj -scheme Clipity -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' archive

mkdir -p "$staging/Payload"
ditto "$archive/Products/Applications/Clipity.app" "$staging/Payload/Clipity.app"
# CODE_SIGNING_ALLOWED=NO leaves this fresh archive unsigned.
ditto -c -k --keepParent "$staging/Payload" "$staging/Clipity-unsigned.ipa"
mv "$staging/Clipity-unsigned.ipa" "$output"
unzip -tq "$output"
printf 'Unsigned IPA: %s\n' "$output"
