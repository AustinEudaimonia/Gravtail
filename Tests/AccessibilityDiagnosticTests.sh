#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="$PROJECT_DIR/Sources/main.swift"

fail() {
  print -u2 "FAIL: $1"
  exit 1
}

# Hardware-only weighting must not create a permission dependency or report a
# misleading TCC state to the user.
grep -Fq 'Gravtail 的硬件加重不需要辅助功能授权' "$SOURCE" \
  || fail "accessibility diagnostic must explain that permission is unnecessary"
if grep -Fq 'AXIsProcessTrusted' "$SOURCE"; then
  fail "hardware-only weighting must not inspect Accessibility trust"
fi

print "AccessibilityDiagnosticTests passed"
