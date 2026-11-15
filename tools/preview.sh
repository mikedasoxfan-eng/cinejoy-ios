#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/previews
xcodebuild -project Cinejoy.xcodeproj -scheme Cinejoy -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x for runtime,devices in d["devices"].items() if "iOS-26" in runtime for x in devices if "iPhone" in x["name"]]; print(candidates[0]["udid"] if candidates else "")')
test -n "$DEVICE_ID"
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" build/Build/Products/Debug-iphonesimulator/Cinejoy.app
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$DEVICE_ID" appearance dark
xcrun simctl launch "$DEVICE_ID" local.cinejoy.glass
sleep 12
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-dark.png
xcrun simctl ui "$DEVICE_ID" appearance light
sleep 2
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-light.png
xcrun simctl ui "$DEVICE_ID" content_size accessibility-large
sleep 2
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-accessibility.png
