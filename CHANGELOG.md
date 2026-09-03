# Changelog

## 0.4.5

- Opened the Accessibility permission flow directly in the correct System
  Settings pane and throttled duplicate permission prompts.
- Started work timing only after the first physical input following launch or
  Reset Session.
- Made mouse/trackpad weighting transactional with rollback on partial HID
  write failures and clearer failure status.
- Waited for older Gravtail instances to exit before this copy can take over
  pointer weighting, followed the pointer across displays, and lowered the
  reminder window level to avoid system dialogs.
- Reduced comet rendering to a 60 FPS budget, improved menu-bar accessibility,
  unified visible UI copy in Chinese, and made packaging rebuild before
  archiving.

## 0.4.4

- Fixed the top menu-bar control being hidden under the camera notch on
  MacBook displays. Gravtail now selects the nearest notch-safe slot beside
  the notch while remaining visually centered.

## 0.4.3

- Replaced the system-managed status item with one deterministic, clickable
  Gravtail mark centered in the notch-safe menu-bar strip. This prevents macOS from
  placing the icon in an invisible overflow slot and keeps it discoverable in
  full-screen apps without creating a duplicate icon. On MacBook displays the
  mark is placed immediately beside the camera notch instead of underneath it.

## 0.4.2

- Removed the duplicate floating menu-bar icon that appeared near the system
  clock. Gravtail now owns one top-center menu-bar control, with its menu and
  click target managed by the app.

## 0.4.1

- Fixed a first-run Accessibility race that could make the pointer appear stuck
  immediately after permission was granted.
- Delayed the global pointer event tap until the cursor is meaningfully heavy,
  skipped no-op cursor warps at near-100% gain, and restored pointer state
  synchronously when changing settings or resetting a session.

## 0.4.0

- Renamed the public app and release artifacts to **Gravtail** while preserving
  the existing bundle identifier for stable macOS permissions.
- Fixed break timing so pre-deadline inactivity does not shorten the configured break.
- Added a compact, content-sized progress reminder pill with the shared dark/orange visual style.
- Added a universal arm64 + x86_64 build.
- Added generated Finder/Dock app artwork from the approved Gravtail mark.
- Added deterministic release packaging, checksums, and a read-only HID diagnostic path.
- Added a fixed self-signed `Heavy Cursor Local` identity setup so TCC approvals
  can survive local/community updates without an Apple Developer membership.
- Unified CI and release artifacts on certificate-backed self-signing; ad-hoc
  packages are rejected.
- Prevented HID acceleration changes unless Accessibility is granted and the
  pointer event tap is active.
