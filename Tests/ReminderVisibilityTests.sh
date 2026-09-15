#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="$PROJECT_DIR/Sources/BreakReminderPanel.swift"

fail() {
  print -u2 "FAIL: $1"
  exit 1
}

# A break reminder must use the status-bar window tier and actively reassert
# its order while visible. A one-time orderFrontRegardless call is not enough
# when another app enters full screen or raises its own floating panel.
grep -Fq 'static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)' "$SOURCE" \
  || fail "break reminder must use a full-screen-safe window tier"
grep -Fq 'panel.level = ReminderWindowLevelPolicy.level' "$SOURCE" \
  || fail "break reminder must use the full-screen-safe window tier"
grep -Fq 'startKeepOnTopMonitoring()' "$SOURCE" \
  || fail "break reminder must start keep-on-top monitoring"
grep -Fq 'reassertOnTopIfNeeded()' "$SOURCE" \
  || fail "break reminder must reassert its z-order while visible"
grep -Fq 'NSWorkspace.activeSpaceDidChangeNotification' "$SOURCE" \
  || fail "break reminder must reassert after a Space or full-screen change"

print "ReminderVisibilityTests passed"
