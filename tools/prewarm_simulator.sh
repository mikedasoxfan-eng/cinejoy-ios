#!/bin/bash
set -euo pipefail
# Called in the background: boot itself can block during first-boot setup.
# preview.sh independently waits for bootstatus before installing/testing.
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x for runtime,devices in d["devices"].items() if "iOS-26" in runtime for x in devices if "iPhone" in x["name"]]; print(candidates[0]["udid"] if candidates else "")')
if [ -n "$DEVICE_ID" ]; then
  echo "Starting Simulator boot early: $DEVICE_ID"
  xcrun simctl boot "$DEVICE_ID" || true
fi
