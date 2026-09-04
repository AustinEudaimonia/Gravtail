#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
TEST_DIR="$(mktemp -d -t gravtail-tests)"
trap 'rm -rf "${TEST_DIR}"' EXIT
TEST_BINARY="${TEST_DIR}/HeavyCursorCoreTests"

swiftc \
  -swift-version 5 \
  "$PROJECT_DIR/Sources/HeavyCursorCore.swift" \
  "$PROJECT_DIR/Tests/HeavyCursorCoreTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

for arch in arm64 x86_64; do
  swiftc \
    -warnings-as-errors \
    -swift-version 5 \
    -typecheck \
    -target "${arch}-apple-macosx13.0" \
    "$PROJECT_DIR"/Sources/*.swift
done

plutil -lint "$PROJECT_DIR/Info.plist" "$PROJECT_DIR/HeavyCursor.entitlements" >/dev/null
zsh -n \
  "$PROJECT_DIR/build.sh" \
  "$PROJECT_DIR/package.sh" \
  "$PROJECT_DIR/scripts/ensure-local-signing-identity.sh" \
  "$PROJECT_DIR/scripts/import-signing-identity.sh" \
  "$PROJECT_DIR/scripts/install-community-build.sh"

if rg -q '@_silgen_name' "$PROJECT_DIR/Sources"; then
  print -u2 "FAIL: private HID symbols must be loaded dynamically"
  exit 1
fi

if ! rg -q 'certificate leaf = H' "$PROJECT_DIR/scripts/install-community-build.sh"; then
  print -u2 "FAIL: installer must verify the exact local signing certificate"
  exit 1
fi

print "Project checks passed"
