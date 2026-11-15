#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/previews
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x for runtime,devices in d["devices"].items() if "iOS-26" in runtime for x in devices if "iPhone" in x["name"]]; print(candidates[0]["udid"] if candidates else "")')
test -n "$DEVICE_ID"
xcodebuild -project Cinejoy.xcodeproj -scheme Cinejoy -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" build/Build/Products/Debug-iphonesimulator/Cinejoy.app
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$DEVICE_ID" appearance dark
SIMCTL_CHILD_CINEJOY_UI_TESTS=1 xcrun simctl launch "$DEVICE_ID" local.cinejoy.glass -appearance dark
sleep 12
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-dark.png
xcrun simctl ui "$DEVICE_ID" appearance light
xcrun simctl terminate "$DEVICE_ID" local.cinejoy.glass
SIMCTL_CHILD_CINEJOY_UI_TESTS=1 xcrun simctl launch "$DEVICE_ID" local.cinejoy.glass -appearance light
sleep 5
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-light.png
xcrun simctl ui "$DEVICE_ID" content_size accessibility-large
xcrun simctl terminate "$DEVICE_ID" local.cinejoy.glass
SIMCTL_CHILD_CINEJOY_UI_TESTS=1 xcrun simctl launch "$DEVICE_ID" local.cinejoy.glass -appearance light
sleep 5
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-accessibility.png
xcrun simctl ui "$DEVICE_ID" content_size large
xcrun simctl ui "$DEVICE_ID" appearance dark
xcrun simctl terminate "$DEVICE_ID" local.cinejoy.glass || true
TEST_RESULT=0
xcodebuild test -project Cinejoy.xcodeproj -scheme Cinejoy -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build \
  -resultBundlePath build/UITests.xcresult -only-testing:CinejoyUITests \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO || TEST_RESULT=$?
xcrun xcresulttool export attachments --path build/UITests.xcresult --output-path dist/previews/ui-tests || true
# Release the iPhone runtime before starting an iPad on the hosted runner.
xcrun simctl shutdown "$DEVICE_ID" || true
IPAD_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x for runtime,devices in d["devices"].items() if "iOS-26" in runtime for x in devices if "iPad" in x["name"]]; print(candidates[0]["udid"] if candidates else "")')
if [ -n "$IPAD_ID" ]; then
  xcrun simctl boot "$IPAD_ID" || true
  xcrun simctl bootstatus "$IPAD_ID" -b
  xcrun simctl install "$IPAD_ID" build/Build/Products/Debug-iphonesimulator/Cinejoy.app
  xcrun simctl ui "$IPAD_ID" appearance dark
  SIMCTL_CHILD_CINEJOY_UI_TESTS=1 xcrun simctl launch "$IPAD_ID" local.cinejoy.glass -appearance dark
  sleep 20
  xcrun simctl io "$IPAD_ID" screenshot dist/previews/ipad-home-dark.png
fi
exit "$TEST_RESULT"
