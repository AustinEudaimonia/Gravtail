#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
TEST_DIR="$(mktemp -d -t gravtail-tests)"
trap 'rm -rf "${TEST_DIR}"' EXIT
TEST_BINARY="${TEST_DIR}/HeavyCursorCoreTests"

swiftc \
  -swift-version 5 \
  "$PROJECT_DIR/Sources/HeavyCursorCore.swift" \
  "$PROJECT_DIR/Tests/HeavyCursorCoreTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

# Link the real application sources and verify that no code path capable of
# intercepting, disconnecting, or warping the global pointer ships in the
# executable. This is a binary-boundary safety contract, not a source grep.
SAFETY_BINARY="${TEST_DIR}/GravtailPointerSafety"
swiftc -swift-version 5 \
  -framework ServiceManagement \
  "$PROJECT_DIR"/Sources/*.swift -o "$SAFETY_BINARY"
unsafe_pointer_symbols="$(nm -u "$SAFETY_BINARY" | grep -E \
  'CGWarpMouseCursorPosition|CGAssociateMouseAndMouseCursorPosition|CGEventTapCreate|AXIsProcessTrusted' \
  || true)"
if [[ -n "$unsafe_pointer_symbols" ]]; then
  print -u2 "FAIL: unsafe global pointer symbol linked into Gravtail"
  print -u2 -- "$unsafe_pointer_symbols"
  exit 1
fi

swiftc -swift-version 5 -warnings-as-errors \
  "$PROJECT_DIR/Sources/RecoveryWatchdog.swift" \
  "$PROJECT_DIR/Tests/RecoveryWatchdogTests.swift" \
  -o "$TEST_DIR/RecoveryWatchdogTests"
"$TEST_DIR/RecoveryWatchdogTests"
/bin/zsh "$PROJECT_DIR/Tests/SigningIdentityTests.sh"
/bin/zsh "$PROJECT_DIR/Tests/SettingsFlowTests.sh"
/bin/zsh "$PROJECT_DIR/Tests/AccessibilityDiagnosticTests.sh"
/bin/zsh "$PROJECT_DIR/Tests/ReminderVisibilityTests.sh"
/bin/zsh "$PROJECT_DIR/Tests/TestHarnessTests.sh"

for arch in arm64 x86_64; do
  swiftc \
    -warnings-as-errors \
    -swift-version 5 \
    -typecheck \
    -target "${arch}-apple-macosx13.0" \
    "$PROJECT_DIR"/Sources/*.swift
done

plutil -lint "$PROJECT_DIR/Info.plist" "$PROJECT_DIR/HeavyCursor.entitlements" >/dev/null
zsh -n \
  "$PROJECT_DIR/build.sh" \
  "$PROJECT_DIR/package.sh" \
  "$PROJECT_DIR/scripts/ensure-local-signing-identity.sh" \
  "$PROJECT_DIR/scripts/import-signing-identity.sh" \
  "$PROJECT_DIR/scripts/install-community-build.sh" \
  "$PROJECT_DIR/scripts/select-signing-identity.sh" \
  "$PROJECT_DIR/Tests/SigningIdentityTests.sh" \
  "$PROJECT_DIR/Tests/SettingsFlowTests.sh" \
  "$PROJECT_DIR/Tests/AccessibilityDiagnosticTests.sh" \
  "$PROJECT_DIR/Tests/ReminderVisibilityTests.sh" \
  "$PROJECT_DIR/Tests/TestHarnessTests.sh" \
  "$PROJECT_DIR/Tests/InstallerIntegrationTests.sh"

if grep -R -q '@_silgen_name' "$PROJECT_DIR/Sources"; then
  print -u2 "FAIL: private HID symbols must be loaded dynamically"
  exit 1
fi

if ! grep -q 'certificate leaf = H' "$PROJECT_DIR/scripts/install-community-build.sh"; then
  print -u2 "FAIL: installer must verify the exact local signing certificate"
  exit 1
fi

backup_names=(
  "Gravtail.previous-20260101-000000-1.app"
  "Gravtail.previous-20260102-000000-2.app"
)
backup_names=("${(@On)backup_names}")
if [[ "${backup_names[1]}" != *20260102* ]]; then
  print -u2 "FAIL: newest installer backup must sort first"
  exit 1
fi

# Run the package-level install/rollback check whenever a signed community
# archive is available. CI source checkouts usually have no release archive,
# so they keep the source-only suite while local release work gets the full
# installer coverage. An explicit path takes precedence over auto-discovery.
installer_archive="${GRAVTAIL_INSTALLER_ARCHIVE:-}"
if [[ -z "${installer_archive}" ]]; then
  setopt null_glob
  installer_archives=("${PROJECT_DIR}"/dist/Gravtail-*-macOS.zip(N))
  if (( ${#installer_archives[@]} == 1 )); then
    installer_archive="${installer_archives[1]}"
  elif (( ${#installer_archives[@]} > 1 )); then
    print "Installer integration skipped: multiple archives found; set GRAVTAIL_INSTALLER_ARCHIVE explicitly."
  fi
fi
if [[ -n "${installer_archive}" ]]; then
  [[ -f "${installer_archive}" ]] || {
    print -u2 "FAIL: installer archive not found: ${installer_archive}"
    exit 1
  }
  /bin/zsh "$PROJECT_DIR/Tests/InstallerIntegrationTests.sh" "${installer_archive}"
else
  print "Installer integration skipped: no Gravtail-<version>-macOS.zip found."
fi

print "Project checks passed"
