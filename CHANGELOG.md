# Changelog

## 0.4.8

- Fixed a critical pointer-freeze bug caused by applying the software event-
  tap gain and system HID acceleration reduction at the same time.
- Made cursor weighting mutually exclusive: precise software weighting during
  active work, native-cursor HID weighting only during the break countdown.
- Bounded the HID path to the same 10% minimum response as the software path;
  Gravtail never intentionally writes a zero acceleration value.
- Explicitly re-associated the physical mouse after every software cursor
  warp and made invalid gain/coordinate states fail open.
- Added per-session circuit breakers: a disabled event tap or failed HID
  operation stays off instead of retrying against live user input.
- Added an independent HID recovery watchdog that restores the saved mouse
  and trackpad values if the main app crashes or is force-killed.
- Made HID updates fully transactional, including rollback of the device whose
  write succeeded but read-back verification failed.
- Made community updates roll back to the previous app if final installation
  verification fails.
- Prevented the installer from mistaking an unrelated shell command that only
  mentions the Gravtail executable path for a running app instance.
- Rebuilt release archives from scratch so removed files cannot survive inside
  an updated ZIP as stale entries.
- Added policy tests that fail if the unsafe dual-weighting path is restored.

## 0.4.7

- Replaced the fragile shared self-signed download flow with a community
  installer that creates and reuses a private local signing identity on each
  user's Mac.
- Community updates are re-signed with the same per-Mac certificate and
  installed to the same Applications path, maximizing Accessibility identity
  continuity without distributing any private signing key.
- The release archive now contains `安装 Gravtail.command`, an installation
  guide, signature checks, a recoverable previous-version backup, and the
  minimal local-signing support files.

## 0.4.6

- Fixed the apparently inert launch state: a subtle comet now appears after
  the first real input instead of staying completely invisible for half of the
  work interval.
- Kept the full comet visible during the break countdown while leaving the
  native pointer and text I-beam behavior untouched.
- Decoupled hardware acceleration reduction from Accessibility trust, so the
  HID layer can still provide a physical cue when the stronger event-tap
  weighting has not been authorized.
- Changed the permission action to request authorization for the exact running
  app once per launch instead of only opening a pane that may contain a stale
  Gravtail entry.
- Added transition-based runtime diagnostics at
  `~/Library/Logs/Gravtail/Gravtail.log`.
- Fixed a recovery-backup ownership bug where the read-only `--check-hid`
  command could erase a running app's saved pre-weight acceleration values.
- HID writes and restores now verify the value read back from macOS, and the
  recovery command no longer claims success when no saved backup exists.
- The local signing setup now verifies and repairs code-signing trust even
  when the `Heavy Cursor Local` identity already exists in Keychain.

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
