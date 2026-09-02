# Gravtail

A deliberately small macOS menu bar app: the longer you use your Mac, the heavier its comet cursor becomes. Step away for the selected break duration and it becomes light again.

## Core behavior

- Choose a 45, 60, or 90 minute work interval.
- Choose a 3, 5, or 10 minute break duration.
- The first half of the session stays visually quiet.
- During the second half, a comet grows continuously and pointer response eases down to 10% at maximum weight.
- Every 15 minutes, a four-second pill reports how long remains before it is time to move.
- At the selected limit, the pill stays visible with a live break countdown and Quit action.
- Pills sit at the upper center of the main screen, below the menu bar and away from bottom-center voice tools such as Typeless.
- A small notch-safe comet/cursor icon sits in the top menu-bar area and opens work and break settings, Reset Session, and Quit.
- Any keyboard or pointer input restarts the break countdown.
- Completing the break restores the original pointer response and starts a new session.
- Reset or quit at any time from the menu bar.

## Build and run

Gravtail supports macOS 13 or later and builds a universal app for Apple
silicon and Intel Macs. Install the Xcode Command Line Tools first.

```sh
./test.sh
./scripts/ensure-local-signing-identity.sh
./build.sh
open ".build/Gravtail.app"
```

The comet works immediately. macOS Accessibility permission is required for
global pointer weighting: open System Settings → Privacy & Security →
Accessibility and enable Gravtail. Without that permission the comet still
works, but Gravtail will not change mouse or trackpad settings.

Gravtail temporarily lowers the active mouse and trackpad acceleration
while the cursor is heavy, backs up the original values first, and restores
them after a completed break or normal quit. If the process is force-killed,
launch it once more so the saved acceleration backup can be restored. A local
build also exposes an explicit emergency command:

```sh
".build/Gravtail.app/Contents/MacOS/HeavyCursor" --restore-hid
```

The app measures physical keyboard and pointer inactivity from macOS HID
events; window redraws, notifications, and changing message content do not
count as work input. It cannot verify whether a person physically stood up.
The configured break duration is therefore a practical inactivity-based proxy
for taking a break.

## Download and install

Download the latest `Gravtail-*-macOS.zip` from GitHub Releases, unzip it,
and move `Gravtail.app` to Applications. This project intentionally uses a
certificate-backed self-signed release, so macOS will require Control-click →
Open on the first launch, followed by the Accessibility permission step above.

macOS identifies privacy-authorized code using its bundle identity and signing
requirements. The setup script creates a certificate-backed self-signed
identity named `Heavy Cursor Local`; the certificate and its private key—not
the display name—are the identity. Keep that exact key pair unchanged for all
official releases, keep the private key out of the repository, and do not
generate a new certificate for every version. A different certificate, Bundle
ID, or unsigned build can require Accessibility approval again.

The public product is named **Gravtail**, while `Heavy Cursor Local` is kept as
the existing signing identity so already-authorized local installations do not
needlessly change code identity. This name is only a certificate/keychain
label; users download and launch `Gravtail.app`.

For a local, non-persistent preview of the full 45-minute effect:

```sh
open ".build/Gravtail.app" --args --preview-45
```

Preview mode does not automatically open the Accessibility permission prompt.
If you want to test physical pointer weighting, choose **Enable Cursor
Weight…** from the menu-bar icon once, or grant Gravtail access manually
in System Settings.

To preview a 15-minute progress pill without waiting:

```sh
open ".build/Gravtail.app" --args --preview-ui --preview-progress
```

## Packaging a self-signed release

```sh
./scripts/ensure-local-signing-identity.sh
./package.sh
```

This produces a universal macOS zip signed with the certificate-backed
`Heavy Cursor Local` identity, a rebuildable source zip, and a
`SHA256SUMS.txt` file in `dist/`. The certificate must already exist in your
login keychain; run the setup script once and keep the resulting certificate
and private key for every release. The app is intentionally self-signed: it
is not notarized, so users must Control-click → Open on first launch.

To use a named fixed self-signed identity, pass that identity explicitly:

```sh
SIGNING_IDENTITY="Heavy Cursor Local" ./package.sh
```

Do not run the identity setup script again on another machine and publish that
build as an update: the same display name does not mean the same certificate.
For GitHub Actions releases, import the original `.p12` certificate as an
encrypted repository secret and use `.github/workflows/release.yml`; never
commit the private key.

The release workflow expects these repository secrets:

- `GRAVTAIL_SIGNING_IDENTITY`: the exact certificate name, normally `Heavy Cursor Local`
- `GRAVTAIL_SIGNING_P12_BASE64`: base64-encoded export of that certificate and private key
- `GRAVTAIL_SIGNING_P12_PASSWORD`: the password used for the `.p12` export

Only the original release certificate should be exported for this purpose. A
new self-signed certificate with the same name changes the code identity and
can cause Accessibility approval to be requested again.

The repository CI also uses a certificate-backed self-signed identity for
testing. Ad-hoc and unsigned packages are intentionally rejected by the build
scripts and are not release formats for Gravtail.

## Attribution

The transparent multi-display overlay and comet approach are based on [MouseTrail](https://github.com/changymon/MouseTrail) by Reggie Chang, used under the MIT License. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
