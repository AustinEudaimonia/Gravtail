#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$BUILD_DIR/Gravtail.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/HeavyCursor.iconset"
ARCHS_STRING="${HEAVY_CURSOR_ARCHS:-arm64 x86_64}"
ARCHS=(${=ARCHS_STRING})
# A fixed certificate-backed identity keeps macOS TCC approvals stable across
# rebuilds. Every build is certificate-signed; ad-hoc signing is deliberately
# unsupported because it cannot provide a stable identity to macOS.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Heavy Cursor Local}"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

if (( ${#ARCHS[@]} == 0 )); then
  print -u2 "HEAVY_CURSOR_ARCHS must contain at least one architecture"
  exit 2
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  print -u2 "Ad-hoc signing is disabled. Use a certificate-backed self-signed identity."
  print -u2 "Run ./scripts/ensure-local-signing-identity.sh, then rebuild."
  exit 2
fi

if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
  print -u2 "Developer ID signing is not part of this free self-signed build."
  print -u2 "Use the fixed self-signed release identity instead."
  exit 2
fi

if ! security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"${SIGNING_IDENTITY}\""; then
  print -u2 "Signing identity not found: ${SIGNING_IDENTITY}"
  print -u2 "Run ./scripts/ensure-local-signing-identity.sh, or import the fixed release identity."
  exit 2
fi

ARCH_BINARIES=()
for arch in $ARCHS; do
  case "$arch" in
    arm64|x86_64) ;;
    *)
      print -u2 "Unsupported architecture: $arch (use arm64 and/or x86_64)"
      exit 2
      ;;
  esac

  output="$BUILD_DIR/HeavyCursor-$arch"
  swiftc \
    -O \
    -swift-version 5 \
    -target "$arch-apple-macosx13.0" \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework IOKit \
    "$PROJECT_DIR"/Sources/*.swift \
    -o "$output"
  ARCH_BINARIES+=("$output")
done

if (( ${#ARCH_BINARIES[@]} == 1 )); then
  cp "${ARCH_BINARIES[1]}" "$MACOS_DIR/HeavyCursor"
else
  lipo -create "${ARCH_BINARIES[@]}" -output "$MACOS_DIR/HeavyCursor"
fi

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_DIR/Resources/HeavyCursorIconMaster.png" "$RESOURCES_DIR/HeavyCursorIconMaster.png"

# Reuse the approved menu-bar artwork as the Finder/Dock icon at all required
# macOS sizes. The iconset is generated in .build so it never pollutes source
# archives.
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PROJECT_DIR/Resources/HeavyCursorIconMaster.png" \
    --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$PROJECT_DIR/Resources/HeavyCursorIconMaster.png" \
    --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
# Self-signed identities are deliberately not timestamped or notarized. They
# are the only supported free local/community release identity.
codesign --force --deep \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$PROJECT_DIR/HeavyCursor.entitlements" \
  "$APP_DIR"

# Fail while building if the bundle is internally inconsistent. This catches
# unsigned nested code and stale resources before an archive is published.
codesign --verify --deep --strict "$APP_DIR"

SIGNATURE_INFO="$(codesign -d -vv "$APP_DIR" 2>&1)"
SIGNER="$(print -r -- "$SIGNATURE_INFO" | awk -F= '/^Authority=/ && !found { print $2; found=1 }')"
if [[ "$SIGNER" != "$SIGNING_IDENTITY" ]]; then
  print -u2 "Signed app identity mismatch: expected '${SIGNING_IDENTITY}', got '${SIGNER:-unknown}'"
  exit 2
fi

echo "$APP_DIR"
