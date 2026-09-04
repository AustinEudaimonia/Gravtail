#!/bin/zsh
set -euo pipefail

IDENTITY_NAME="${1:-${HEAVY_CURSOR_LOCAL_IDENTITY:-Heavy Cursor Local}}"
KEYCHAIN="$(security default-keychain -d user | sed -e 's/^ *//' -e 's/\"//g')"

ensure_code_signing_trust() {
  local trust_dir="$(mktemp -d -t heavy-cursor-trust)"
  local public_cert="${trust_dir}/identity.cer"

  security find-certificate -c "${IDENTITY_NAME}" -p > "${public_cert}"
  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "${KEYCHAIN}" \
    "${public_cert}" >/dev/null
  security verify-cert -p codeSign -c "${public_cert}" >/dev/null
  rm -rf "${trust_dir}"
}

if security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"${IDENTITY_NAME}\""; then
  ensure_code_signing_trust
  print "Using existing code-signing identity: ${IDENTITY_NAME}"
  print "Verified user-level code-signing trust for: ${IDENTITY_NAME}"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  print -u2 "OpenSSL is required to create the local signing identity."
  exit 1
fi

WORK_DIR="$(mktemp -d -t heavy-cursor-signing)"
trap 'rm -rf "${WORK_DIR}"' EXIT

CONFIG="${WORK_DIR}/codesign.cnf"
KEY="${WORK_DIR}/identity.key"
CERT="${WORK_DIR}/identity.cer"
P12="${WORK_DIR}/identity.p12"
P12_PASSWORD="$(uuidgen)"

cat >"${CONFIG}" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = codesign
prompt = no

[ req_distinguished_name ]
CN = ${IDENTITY_NAME}

[ codesign ]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

print "Creating local code-signing identity: ${IDENTITY_NAME}"
openssl req \
  -new \
  -newkey rsa:2048 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -keyout "${KEY}" \
  -out "${CERT}" \
  -subj "/CN=${IDENTITY_NAME}" \
  -config "${CONFIG}" \
  -extensions codesign >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -inkey "${KEY}" \
  -in "${CERT}" \
  -out "${P12}" \
  -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1

security import "${P12}" \
  -k "${KEYCHAIN}" \
  -P "${P12_PASSWORD}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

# Trust only this certificate for code signing in the user's login keychain.
# It is not installed as a system-wide TLS or web trust root.
ensure_code_signing_trust

if ! security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"${IDENTITY_NAME}\""; then
  print -u2 "The certificate was created, but macOS did not expose it as a valid code-signing identity."
  print -u2 "Open Keychain Access and verify that '${IDENTITY_NAME}' has a private key and is trusted for code signing."
  exit 1
fi

print "Created code-signing identity in the login keychain: ${IDENTITY_NAME}"
print "Keep this exact certificate and private key unchanged so macOS can preserve Accessibility approval across updates."
print "The identity name alone is not portable; another Mac must import this same certificate and private key."
