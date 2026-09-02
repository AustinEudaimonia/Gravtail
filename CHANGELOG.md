# Changelog

## 0.4.3

- Replaced the system-managed status item with one deterministic, clickable
  Gravtail mark centered in the menu-bar strip. This prevents macOS from
  placing the icon in an invisible overflow slot and keeps it discoverable in
  full-screen apps without creating a duplicate icon.

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
