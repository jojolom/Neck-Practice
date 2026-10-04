#!/bin/bash
# Archive Neck Practice and upload it to App Store Connect (lands in TestFlight).
# Credentials live outside the repo in ~/.appstoreconnect/neck-practice.env:
#   ASC_KEY_ID=XXXXXXXXXX
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# with the key file at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
set -euo pipefail

cd "$(dirname "$0")/.."
source "$HOME/.appstoreconnect/neck-practice.env"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

# Build number: timestamp, always increasing. Version comes from MARKETING_VERSION in the project.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
OUT="build/release-$BUILD_NUMBER"

xcodebuild archive \
  -project "Guitar Man.xcodeproj" -scheme "Guitar Man" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/NeckPractice.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${AUTH[@]}"

xcodebuild -exportArchive \
  -archivePath "$OUT/NeckPractice.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist scripts/ExportOptions.plist "${AUTH[@]}"

echo "Uploaded build $BUILD_NUMBER. It appears in TestFlight after Apple finishes processing (~5-15 min)."
