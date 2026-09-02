#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  print -u2 "Usage: GRAVTAIL_SIGNING_P12_PASSWORD=... $0 <identity-name> <identity.p12>"
  exit 2
fi

IDENTITY_NAME="$1"
P12_PATH="$2"
P12_PASSWORD="${GRAVTAIL_SIGNING_P12_PASSWORD:-}"

if [[ -z "$P12_PASSWORD" ]]; then
  print -u2 "GRAVTAIL_SIGNING_P12_PASSWORD is required."
  exit 2
fi
if [[ ! -f "$P12_PATH" ]]; then
  print -u2 "Signing identity file not found: $P12_PATH"
  exit 2
fi

KEYCHAIN="$(security default-keychain -d user | sed -e 's/^ *//' -e 's/"//g')"
security import "$P12_PATH" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

# Trust only this certificate for code signing in the user's login keychain.
# The certificate is never added as a TLS or web trust root.
WORK_DIR="$(mktemp -d -t gravtail-signing-import)"
trap 'rm -rf "$WORK_DIR"' EXIT
CERT_PATH="$WORK_DIR/identity.cer"
security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN" > "$CERT_PATH"
security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT_PATH" >/dev/null

if ! security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"${IDENTITY_NAME}\""; then
  print -u2 "Imported certificate is not available as a code-signing identity: ${IDENTITY_NAME}"
  exit 1
fi

print "Imported fixed self-signing identity: ${IDENTITY_NAME}"
