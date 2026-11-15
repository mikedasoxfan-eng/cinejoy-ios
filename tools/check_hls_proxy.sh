#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/checks
CHECK_KEY=$({ swiftc --version; cat Sources/HLSPlaylist.swift tests/hls-proxy/main.swift; } | shasum -a 256 | cut -d ' ' -f 1)
if [ "$(cat build/checks/hls-key 2>/dev/null || true)" != "$CHECK_KEY" ] || [ ! -x build/checks/check-hls-proxy ]; then
  swiftc Sources/HLSPlaylist.swift tests/hls-proxy/main.swift -o build/checks/check-hls-proxy
  printf '%s' "$CHECK_KEY" > build/checks/hls-key
fi
build/checks/check-hls-proxy
