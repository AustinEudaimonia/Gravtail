#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$BUILD_DIR/Gravtail.app"
DIST_DIR="$PROJECT_DIR/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
APP_ZIP="$DIST_DIR/Gravtail-${VERSION}-macOS.zip"
SOURCE_ZIP="$DIST_DIR/Gravtail-${VERSION}-source.zip"
CHECKSUMS="$DIST_DIR/Gravtail-${VERSION}-SHA256SUMS.txt"
SIGNING_IDENTITY_VALUE="${SIGNING_IDENTITY:-Heavy Cursor Local}"

mkdir -p "$DIST_DIR"
if [[ "$SIGNING_IDENTITY_VALUE" == "-" ]]; then
  print -u2 "Ad-hoc packages are disabled. Use a certificate-backed self-signed identity."
  exit 2
fi

if [[ "$SIGNING_IDENTITY_VALUE" == Developer\ ID\ Application:* ]]; then
  print -u2 "Developer ID packages are not part of this free self-signed release."
  exit 2
fi

print "Creating a certificate-backed self-signed package with identity: ${SIGNING_IDENTITY_VALUE}"
print "Users will need Control-click → Open on first launch; notarization is unavailable."

if [[ "$SIGNING_IDENTITY_VALUE" != "-" ]] && ! security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"${SIGNING_IDENTITY_VALUE}\""; then
  print -u2 "Signing identity not found: ${SIGNING_IDENTITY_VALUE}"
  print -u2 "Run ./scripts/ensure-local-signing-identity.sh or pass a valid SIGNING_IDENTITY."
  exit 2
fi

# Export explicitly so package.sh cannot accidentally build with a different
# identity than the one it reports and validates.
# --norsrc keeps Finder resource-fork metadata out of the release archive.
ditto -c -k --norsrc --keepParent "$APP_DIR" "$APP_ZIP"

source_stage="$(mktemp -d -t heavy-cursor-source)"
trap 'rm -rf "$source_stage"' EXIT
mkdir -p "$source_stage/Gravtail"
cp "$PROJECT_DIR"/{.gitignore,CHANGELOG.md,HeavyCursor.entitlements,Info.plist,LICENSE,README.md,THIRD_PARTY_NOTICES.md,build.sh,package.sh,test.sh} "$source_stage/Gravtail/"
cp -R "$PROJECT_DIR/Sources" "$PROJECT_DIR/Tests" "$PROJECT_DIR/Resources" "$source_stage/Gravtail/"
cp -R "$PROJECT_DIR/scripts" "$source_stage/Gravtail/"
if [[ -d "$PROJECT_DIR/.github" ]]; then
  cp -R "$PROJECT_DIR/.github" "$source_stage/Gravtail/"
fi

(cd "$source_stage" && COPYFILE_DISABLE=1 zip -qr -X "$SOURCE_ZIP" Gravtail)
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$APP_ZIP")" "$(basename "$SOURCE_ZIP")" > "$(basename "$CHECKSUMS")")

print "Created: $APP_ZIP"
print "Created: $SOURCE_ZIP"
print "Created: $CHECKSUMS"
