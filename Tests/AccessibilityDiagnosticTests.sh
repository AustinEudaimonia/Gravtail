#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="$PROJECT_DIR/Sources/main.swift"

fail() {
  print -u2 "FAIL: $1"
  exit 1
}

# A command-line invocation runs as the terminal process for TCC purposes; it
# must never claim that the bundled Gravtail.app itself is trusted.
grep -Fq '命令行模式不能代表 Gravtail.app' "$SOURCE" \
  || fail "accessibility diagnostic must explain app-context checking"
if grep -Fq 'print(AXIsProcessTrusted() ? "trusted" : "not-trusted")' "$SOURCE"; then
  fail "command-line accessibility probe must not report the terminal trust state"
fi

print "AccessibilityDiagnosticTests passed"
