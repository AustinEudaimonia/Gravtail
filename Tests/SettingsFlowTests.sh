#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="$PROJECT_DIR/Sources/main.swift"

fail() {
  print -u2 "FAIL: $1"
  exit 1
}

grep -Fq 'physicalWeightingEnabled ? "确认" : "开启鼠标加重"' "$SOURCE" || fail "settings need a direct hardware-weighting confirmation label"
grep -Fq '@objc private func confirmSettings()' "$SOURCE" || fail "confirm button needs a dedicated dismissal action"
grep -Fq 'SMAppService.openSystemSettingsLoginItems()' "$SOURCE" || fail "login-item guidance must open the native System Settings page"
grep -Fq 'showLoginItemPromptIfNeeded()' "$SOURCE" || fail "first-run flow must offer login-item setup guidance"
grep -Fq '配置开机启动…' "$SOURCE" || fail "settings need a persistent login-item setup entry"

grep -Fq 'pointerController' "$SOURCE" && fail "settings must not depend on a global pointer event tap"
grep -Fq '辅助功能权限' "$SOURCE" && fail "hardware-only weighting must not request Accessibility permission"

# The menu-bar entry must have one owner at a time. A status-bar-level NSPanel
# is allowed only as a delayed fallback after the native item is removed.
grep -Fq 'MenuBarFallbackPolicy.shouldUseFallback' "$SOURCE" || fail "menu bar fallback must use the hidden-menu-bar policy"
grep -Fq 'NSStatusBar.system.removeStatusItem(item)' "$SOURCE" || fail "fallback must remove the native status item first"
grep -Fq 'fallbackProductIconPanel' "$SOURCE" || fail "fallback panel needs an explicit single-owner state"

confirm_body="$(sed -n '/@objc private func confirmSettings()/,/^    }/p' "$SOURCE")"
print -r -- "$confirm_body" | grep -Fq 'settingsWindow?.orderOut(nil)' || fail "confirm must only collapse the settings window"
print -r -- "$confirm_body" | grep -Fq 'NSApp.terminate' && fail "confirm must not terminate Gravtail"

print "SettingsFlowTests passed"
