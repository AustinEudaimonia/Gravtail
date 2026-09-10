#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="$PROJECT_DIR/Sources/main.swift"

fail() {
  print -u2 "FAIL: $1"
  exit 1
}

grep -Fq 'pointerController.isTrusted ? "确认"' "$SOURCE" || fail "trusted settings need a dedicated confirm label"
grep -Fq '@objc private func confirmSettings()' "$SOURCE" || fail "confirm button needs a dedicated dismissal action"

confirm_body="$(sed -n '/@objc private func confirmSettings()/,/^    }/p' "$SOURCE")"
print -r -- "$confirm_body" | grep -Fq 'settingsWindow?.orderOut(nil)' || fail "confirm must only collapse the settings window"
print -r -- "$confirm_body" | grep -Fq 'NSApp.terminate' && fail "confirm must not terminate Gravtail"

print "SettingsFlowTests passed"
