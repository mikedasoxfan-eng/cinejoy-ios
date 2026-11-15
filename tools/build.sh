#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 1; }
bash tools/check_hls_proxy.sh
swift tools/Icon.swift Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
xcodegen generate
xcodebuild -project Cinejoy.xcodeproj -scheme Cinejoy -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p dist/Payload
ditto build/Build/Products/Release-iphoneos/Cinejoy.app dist/Payload/Cinejoy.app
(cd dist && ditto -c -k --keepParent Payload Cinejoy-unsigned.ipa)
python3 tools/verify_ipa.py dist/Cinejoy-unsigned.ipa > dist/verification.json
echo "Created $(pwd)/dist/Cinejoy-unsigned.ipa — re-sign with your sideloading tool."
