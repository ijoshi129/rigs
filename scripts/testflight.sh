#!/usr/bin/env bash
# Archives Rigs and uploads it to TestFlight using an App Store Connect API key,
# so no Apple ID has to be signed in to Xcode.
#
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-... scripts/testflight.sh
#
# The key file is read from ~/.appstoreconnect/AuthKey_<ASC_KEY_ID>.p8 unless
# ASC_KEY_PATH is set. The build number is the git commit count, so every
# upload is unique.
set -euo pipefail

: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/AuthKey_${ASC_KEY_ID}.p8}"

cd "$(dirname "$0")/.."
OUT="${OUT:-build/testflight}"
BUILD_NUMBER="$(git rev-list --count HEAD)"
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

xcodegen generate
rm -rf "$OUT"

xcodebuild archive \
  -project Rigs.xcodeproj -scheme Rigs -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Rigs.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${AUTH[@]}"

xcodebuild -exportArchive \
  -archivePath "$OUT/Rigs.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$OUT" \
  "${AUTH[@]}"

echo "Uploaded build $BUILD_NUMBER. It appears in TestFlight after Apple finishes processing (usually 5–15 minutes)."
