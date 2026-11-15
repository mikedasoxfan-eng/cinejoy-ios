#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 1; }
BUILD_STARTED=$(date +%s)
mkdir -p build dist
python3 tools/restore_build_inputs.py
bash tools/check_hls_proxy.sh
ICON_KEY=$(cat tools/Icon.swift Resources/Brand/pwa-512.png | shasum -a 256 | cut -d ' ' -f 1)
if [ "$(cat build/icon-key 2>/dev/null || true)" != "$ICON_KEY" ] || [ ! -f build/generated/AppIcon.png ]; then
  swift tools/Icon.swift Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
  mkdir -p build/generated
  cp -p dist/AppIcon.png build/generated/AppIcon.png
  printf '%s' "$ICON_KEY" > build/icon-key
else
  cp -p build/generated/AppIcon.png Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
  cp -p build/generated/AppIcon.png dist/AppIcon.png
fi
xcodegen generate --use-cache
COMPILE_STARTED=$(date +%s)
xcodebuild -project Cinejoy.xcodeproj -scheme Cinejoy -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO SWIFT_COMPILATION_MODE=incremental \
  COMPILATION_CACHE_ENABLE_CACHING=YES COMPILER_INDEX_STORE_ENABLE=NO \
  -quiet build
COMPILE_FINISHED=$(date +%s)
mkdir -p dist/Payload
ditto build/Build/Products/Release-iphoneos/Cinejoy.app dist/Payload/Cinejoy.app
(cd dist && ditto -c -k --keepParent Payload Cinejoy-unsigned.ipa)
# Standard IPA artwork also lets sideloading tools preview the updated icon.
cp dist/AppIcon.png dist/iTunesArtwork@2x
(cd dist && zip -q Cinejoy-unsigned.ipa iTunesArtwork@2x)
python3 tools/verify_ipa.py dist/Cinejoy-unsigned.ipa > dist/verification.json
export BUILD_STARTED COMPILE_STARTED COMPILE_FINISHED
python3 tools/build_metrics.py > dist/build-metrics.json
cat dist/build-metrics.json
echo "Created $(pwd)/dist/Cinejoy-unsigned.ipa — re-sign with your sideloading tool."
