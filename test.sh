#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
TEST_BINARY="$(mktemp -d)/HeavyCursorCoreTests"

swiftc \
  -swift-version 5 \
  "$PROJECT_DIR/Sources/HeavyCursorCore.swift" \
  "$PROJECT_DIR/Tests/HeavyCursorCoreTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
