#!/bin/zsh
set -euo pipefail

# Optional signed-package integration check. Uses an isolated install root,
# never launches the app or registers it with the user's Launch Services.
archive="${1:?provide a signed Gravtail community ZIP}"
test_dir="$(mktemp -d -t gravtail-installer-test)"
ditto -x -k "${archive}" "${test_dir}/package"
packages=("${test_dir}/package"/Gravtail-*(/N))
[[ ${#packages[@]} == 1 ]]
package="${packages[1]}"
mkdir "${test_dir}/Applications"
target="${test_dir}/Applications/Gravtail.app"
ditto "${package}/Gravtail.app" "${target}"
codesign -d --extract-certificates="${test_dir}/original-cert-" "${target}" 2>/dev/null
fingerprint="$(openssl x509 -inform DER -in "${test_dir}/original-cert-0" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"

backup_root="${test_dir}/Backups"
GRAVTAIL_INSTALL_DIR="${test_dir}/Applications" GRAVTAIL_BACKUP_DIR="${backup_root}" \
  GRAVTAIL_SKIP_LAUNCH=1 GRAVTAIL_SKIP_REGISTRATION=1 \
  /bin/zsh "${package}/安装 Gravtail.command"
codesign --verify --deep --strict -R="certificate leaf = H\"${fingerprint}\"" "${target}"
backups=("${backup_root}"/Gravtail.previous-*.app(N))
[[ ${#backups[@]} == 1 ]]
old_in_apps=("${test_dir}/Applications"/Gravtail.previous-*.app(N))
[[ ${#old_in_apps[@]} == 0 ]]
cmp "${package}/Gravtail.app/Contents/Info.plist" "${target}/Contents/Info.plist"
source_hash="$(codesign -d -vvvv "${package}/Gravtail.app" 2>&1 | awk -F= '/^CDHash=/ {print $2}')"
installed_hash="$(codesign -d -vvvv "${target}" 2>&1 | awk -F= '/^CDHash=/ {print $2}')"
[[ -n "${source_hash}" && "${source_hash}" == "${installed_hash}" ]]
print 'InstallerIntegrationTests passed: exact original certificate retained; rollback copy preserved; no launch or registration'
print "Isolated test files: ${test_dir}"
