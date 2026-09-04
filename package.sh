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

print "Creating a locally re-signable community package from identity: ${SIGNING_IDENTITY_VALUE}"
print "Each user's installer will replace this signature with a private per-Mac identity."

if [[ "$SIGNING_IDENTITY_VALUE" != "-" ]] && ! security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"${SIGNING_IDENTITY_VALUE}\""; then
  print -u2 "Signing identity not found: ${SIGNING_IDENTITY_VALUE}"
  print -u2 "Run ./scripts/ensure-local-signing-identity.sh or pass a valid SIGNING_IDENTITY."
  exit 2
fi

# Always rebuild before packaging. Without this guard, a release command can
# silently archive a stale or missing .build/Gravtail.app from an earlier
# checkout.
SIGNING_IDENTITY="$SIGNING_IDENTITY_VALUE" "$PROJECT_DIR/build.sh" >/dev/null
if [[ ! -x "$APP_DIR/Contents/MacOS/HeavyCursor" ]]; then
  print -u2 "Build completed without a runnable Gravtail executable: $APP_DIR"
  exit 2
fi

package_stage="$(mktemp -d -t gravtail-package)"
trap 'rm -rf "$package_stage"' EXIT

# The public community archive contains a local re-signing installer. Each Mac
# creates its own stable certificate and reuses it for future updates, avoiding
# a shared private key or a different TCC identity on every build.
install_stage="$package_stage/Gravtail-${VERSION}"
mkdir -p "$install_stage/Support"
ditto "$APP_DIR" "$install_stage/Gravtail.app"
cp "$PROJECT_DIR/scripts/install-community-build.sh" "$install_stage/安装 Gravtail.command"
cp "$PROJECT_DIR/scripts/ensure-local-signing-identity.sh" "$install_stage/Support/ensure-local-signing-identity.sh"
cp "$PROJECT_DIR/HeavyCursor.entitlements" "$install_stage/Support/HeavyCursor.entitlements"
cp "$PROJECT_DIR/COMMUNITY_INSTALL.md" "$install_stage/安装说明.md"
chmod +x "$install_stage/安装 Gravtail.command" "$install_stage/Support/ensure-local-signing-identity.sh"
ditto -c -k --norsrc --keepParent "$install_stage" "$APP_ZIP"

source_stage="$package_stage/source"
mkdir -p "$source_stage"
mkdir -p "$source_stage/Gravtail"
cp "$PROJECT_DIR"/{.gitignore,CHANGELOG.md,COMMUNITY_INSTALL.md,HeavyCursor.entitlements,Info.plist,LICENSE,README.md,THIRD_PARTY_NOTICES.md,build.sh,package.sh,test.sh} "$source_stage/Gravtail/"
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
