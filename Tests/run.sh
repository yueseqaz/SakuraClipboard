#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -framework Cocoa Sources/StatusBarIcon.swift Tests/StatusBarIconTests.swift \
  -o "$TEST_DIR/StatusBarIconTests"
"$TEST_DIR/StatusBarIconTests"
SOURCES=()
for source in Sources/*.swift; do
  if [[ "$source" != "Sources/main.swift" ]]; then SOURCES+=("$source"); fi
done
swiftc -framework Cocoa -framework ServiceManagement -framework Carbon -lsqlite3 \
  "${SOURCES[@]}" Tests/HistoryHoverTests.swift \
  -o "$TEST_DIR/HistoryHoverTests"
"$TEST_DIR/HistoryHoverTests"
swiftc -framework Cocoa -framework ServiceManagement -framework Carbon -lsqlite3 \
  "${SOURCES[@]}" Tests/ClipboardSourceTests.swift \
  -o "$TEST_DIR/ClipboardSourceTests"
"$TEST_DIR/ClipboardSourceTests"
