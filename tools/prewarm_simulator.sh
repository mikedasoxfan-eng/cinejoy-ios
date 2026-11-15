#!/bin/bash
set -euo pipefail
# boot returns before first-boot migration finishes. Let that work overlap the
# device and Simulator compilations; preview.sh still waits for bootstatus.
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x for runtime,devices in d["devices"].items() if "iOS-26" in runtime for x in devices if "iPhone" in x["name"]]; print(candidates[0]["udid"] if candidates else "")')
if [ -n "$DEVICE_ID" ]; then
  echo "Starting Simulator boot early: $DEVICE_ID"
  xcrun simctl boot "$DEVICE_ID" || true
fi
