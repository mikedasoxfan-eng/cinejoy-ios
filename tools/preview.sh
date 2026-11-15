#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Pushes publish a device IPA immediately. Deliberate manual QA retains the full
# native screen suite; a test runtime's first boot must not hold up every edit.
if [ "${GITHUB_EVENT_NAME:-}" = push ] && [ -z "${CINEJOY_QA_FOCUS:-}" ]; then
  echo 'Fast IPA build: Simulator QA runs on manual workflow dispatch.'
  exit 0
fi
mkdir -p dist/previews
QA_FOCUS=${CINEJOY_QA_FOCUS:-full}
if [ -z "${CINEJOY_QA_FOCUS:-}" ]; then
  case "${GITHUB_REF_NAME:-}" in
    qa/player*) QA_FOCUS=player ;;
    qa/interface*) QA_FOCUS=interface ;;
    qa/handoff*) QA_FOCUS=handoff ;;
    qa/fullscreen*) QA_FOCUS=fullscreen ;;
    qa/captions*) QA_FOCUS=captions ;;
  esac
fi
case "$QA_FOCUS" in
  full|player|interface|handoff|fullscreen|captions) ;;
  *) echo "Unsupported CINEJOY_QA_FOCUS: $QA_FOCUS" >&2; exit 2 ;;
esac
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x for runtime,devices in d["devices"].items() if "iOS-26" in runtime for x in devices if "iPhone" in x["name"]]; print(candidates[0]["udid"] if candidates else "")')
test -n "$DEVICE_ID"
xcrun simctl boot "$DEVICE_ID" || true
if [ "$QA_FOCUS" = captions ]; then
  swift tools/MakeCaptionFixture.swift Resources/CaptionQAFixture.mp4
  xcodegen generate --use-cache
fi
xcodebuild -project Cinejoy.xcodeproj -scheme Cinejoy -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" build/Build/Products/Debug-iphonesimulator/Cinejoy.app
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$DEVICE_ID" appearance dark
xcrun simctl ui "$DEVICE_ID" content_size large
TEST_SELECTION=(-only-testing:CinejoyUITests)
if [ "$QA_FOCUS" = player ]; then
  TEST_SELECTION=(
    -only-testing:CinejoyUITests/CinejoyUITests/testPlaybackHistoryAndNoCasting
    -only-testing:CinejoyUITests/CinejoyUITests/testAVKitFullscreenRoundTripKeepsPlayback
    -only-testing:CinejoyUITests/CinejoyUITests/testTVSeasonSelection
  )
elif [ "$QA_FOCUS" = handoff ]; then
  TEST_SELECTION=(-only-testing:CinejoyUITests/CinejoyUITests/testTVSeasonSelection)
elif [ "$QA_FOCUS" = fullscreen ]; then
  TEST_SELECTION=(-only-testing:CinejoyUITests/CinejoyUITests/testAVKitFullscreenRoundTripKeepsPlayback)
elif [ "$QA_FOCUS" = captions ]; then
  TEST_SELECTION=(
    -only-testing:CinejoyUITests/CinejoyUITests/testNativeCaptionRenderer
    -only-testing:CinejoyUITests/CinejoyUITests/testLiveSubtitleBridge
  )
elif [ "$QA_FOCUS" = interface ]; then
  TEST_SELECTION=(
    -only-testing:CinejoyUITests/CinejoyUITests/testHomeScreenCapture
    -only-testing:CinejoyUITests/CinejoyUITests/testLightHomeHeroCapture
    -only-testing:CinejoyUITests/CinejoyUITests/testNativeBrowsingAndLocalLibrary
    -only-testing:CinejoyUITests/CinejoyUITests/testSearchEmptyStateAndLiveResults
    -only-testing:CinejoyUITests/CinejoyUITests/testSettingsAppearance
  )
fi
TEST_RESULT=0
xcodebuild test -project Cinejoy.xcodeproj -scheme Cinejoy -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build \
  -resultBundlePath build/UITests.xcresult "${TEST_SELECTION[@]}" \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO || TEST_RESULT=$?
xcrun xcresulttool export attachments --path build/UITests.xcresult --output-path dist/previews/ui-tests || true
if [ "$QA_FOCUS" = player ] || [ "$QA_FOCUS" = handoff ] || [ "$QA_FOCUS" = fullscreen ] || [ "$QA_FOCUS" = captions ]; then
  xcrun simctl shutdown "$DEVICE_ID" || true
  exit "$TEST_RESULT"
fi
# Run native UI tests first so their interruption handler dismisses first-boot
# Simulator banners before the standalone appearance captures.
xcrun simctl terminate "$DEVICE_ID" local.cinejoy.glass || true
xcrun simctl ui "$DEVICE_ID" appearance dark
SIMCTL_CHILD_CINEJOY_UI_TESTS=1 xcrun simctl launch "$DEVICE_ID" local.cinejoy.glass -appearance dark
sleep 12
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-dark.png
xcrun simctl terminate "$DEVICE_ID" local.cinejoy.glass
xcrun simctl ui "$DEVICE_ID" appearance light
SIMCTL_CHILD_CINEJOY_UI_TESTS=1 xcrun simctl launch "$DEVICE_ID" local.cinejoy.glass -appearance light
sleep 5
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-light.png
xcrun simctl terminate "$DEVICE_ID" local.cinejoy.glass
xcrun simctl ui "$DEVICE_ID" content_size accessibility-large
SIMCTL_CHILD_CINEJOY_UI_TESTS=1 xcrun simctl launch "$DEVICE_ID" local.cinejoy.glass -appearance light
sleep 5
xcrun simctl io "$DEVICE_ID" screenshot dist/previews/home-accessibility.png
xcrun simctl ui "$DEVICE_ID" content_size large
xcrun simctl ui "$DEVICE_ID" appearance dark
xcrun simctl terminate "$DEVICE_ID" local.cinejoy.glass || true
# Release the iPhone runtime before starting an iPad on the hosted runner.
xcrun simctl shutdown "$DEVICE_ID" || true
if [ "$QA_FOCUS" = interface ]; then
  exit "$TEST_RESULT"
fi
IPAD_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x for runtime,devices in d["devices"].items() if "iOS-26" in runtime for x in devices if "iPad" in x["name"]]; print(candidates[0]["udid"] if candidates else "")')
if [ -n "$IPAD_ID" ]; then
  xcrun simctl boot "$IPAD_ID" || true
  xcrun simctl bootstatus "$IPAD_ID" -b
  xcrun simctl install "$IPAD_ID" build/Build/Products/Debug-iphonesimulator/Cinejoy.app
  xcrun simctl status_bar "$IPAD_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
  xcrun simctl ui "$IPAD_ID" appearance dark
  xcrun simctl ui "$IPAD_ID" content_size large
  IPAD_RESULT=0
  xcodebuild test -project Cinejoy.xcodeproj -scheme Cinejoy -configuration Debug \
    -destination "platform=iOS Simulator,id=$IPAD_ID" -derivedDataPath build \
    -resultBundlePath build/IPadUITests.xcresult \
    -only-testing:CinejoyUITests/CinejoyUITests/testHomeScreenCapture \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO || IPAD_RESULT=$?
  xcrun xcresulttool export attachments --path build/IPadUITests.xcresult --output-path dist/previews/ipad-ui-tests || true
  python3 - <<'PY'
import json
import pathlib
import shutil
root = pathlib.Path('dist/previews/ipad-ui-tests')
manifest = root / 'manifest.json'
if manifest.exists():
    for test in json.loads(manifest.read_text()):
        for attachment in test.get('attachments', []):
            name = attachment.get('suggestedHumanReadableName', '')
            source = root / attachment.get('exportedFileName', '')
            if name.startswith('home-screen') and source.suffix == '.png':
                shutil.copyfile(source, root.parent / 'ipad-home-dark.png')
PY
  if [ "$TEST_RESULT" -eq 0 ]; then TEST_RESULT=$IPAD_RESULT; fi
  xcrun simctl shutdown "$IPAD_ID" || true
fi
exit "$TEST_RESULT"
