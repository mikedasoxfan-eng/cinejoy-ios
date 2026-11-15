#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET_DIR=$(mktemp -d)
trap 'rm -f "$TARGET_DIR/check-hls-proxy"; rmdir "$TARGET_DIR"' EXIT
swiftc Sources/HLSPlaylist.swift tests/hls-proxy/main.swift -o "$TARGET_DIR/check-hls-proxy"
"$TARGET_DIR/check-hls-proxy"
