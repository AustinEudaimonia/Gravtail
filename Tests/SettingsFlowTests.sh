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
grep -Fq '提醒音效' "$SOURCE" || fail "settings need a reminder-sound toggle"
grep -Fq 'reminderSoundPlayer.play(.progress)' "$SOURCE" || fail "progress reminders need a sound cue"
grep -Fq 'reminderSoundPlayer.play(.breakStarted)' "$SOURCE" || fail "break start needs a sound cue"
grep -Fq 'reminderSoundPlayer.play(.breakEnded)' "$SOURCE" || fail "break completion needs a sound cue"

grep -Fq 'pointerController' "$SOURCE" && fail "settings must not depend on a global pointer event tap"
grep -Fq '辅助功能权限' "$SOURCE" && fail "hardware-only weighting must not request Accessibility permission"

# The formal app must use one macOS-managed status item. It must never replace
# that item with a floating panel based on transient geometry values.
grep -Fq 'NSStatusItem.squareLength' "$SOURCE" || fail "formal menu bar item must use the native square length"
grep -Fq 'item.autosaveName' "$SOURCE" || fail "formal menu bar item needs a stable autosave name"
grep -Fq 'statusItem = item' "$SOURCE" || fail "formal app must retain the native status item"
grep -Fq 'fallbackProductIconPanel' "$SOURCE" && fail "formal app must not create a floating menu bar fallback"
grep -Fq 'MenuBarFallbackPolicy' "$SOURCE" && fail "formal app must not infer menu bar visibility from transient geometry"
grep -Fq 'NSStatusBar.system.removeStatusItem(item)' "$SOURCE" && fail "formal app must not remove its native status item during startup"

confirm_body="$(sed -n '/@objc private func confirmSettings()/,/^    }/p' "$SOURCE")"
print -r -- "$confirm_body" | grep -Fq 'settingsWindow?.orderOut(nil)' || fail "confirm must only collapse the settings window"
print -r -- "$confirm_body" | grep -Fq 'NSApp.terminate' && fail "confirm must not terminate Gravtail"

print "SettingsFlowTests passed"
