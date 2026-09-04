#!/bin/zsh
set -euo pipefail

PACKAGE_DIR="${0:A:h}"
SOURCE_APP="${PACKAGE_DIR}/Gravtail.app"
SUPPORT_DIR="${PACKAGE_DIR}/Support"
IDENTITY_NAME="${GRAVTAIL_LOCAL_IDENTITY:-Gravtail Local}"
INSTALL_ROOT="${GRAVTAIL_INSTALL_DIR:-/Applications}"
EXPECTED_BUNDLE_ID="com.spark.heavycursor"

fail() {
  print -u2 "安装失败：$1"
  exit 1
}

[[ -d "${SOURCE_APP}" ]] || fail "安装包中缺少 Gravtail.app。请完整解压 ZIP 后再运行。"
[[ -x "${SUPPORT_DIR}/ensure-local-signing-identity.sh" ]] || fail "安装包中的签名工具不完整。"
[[ -f "${SUPPORT_DIR}/HeavyCursor.entitlements" ]] || fail "安装包中缺少签名权限文件。"

actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${SOURCE_APP}/Contents/Info.plist" 2>/dev/null || true)"
[[ "${actual_bundle_id}" == "${EXPECTED_BUNDLE_ID}" ]] || fail "Bundle ID 不匹配，拒绝安装。"
codesign --verify --deep --strict "${SOURCE_APP}" 2>/dev/null || fail "下载的 App 签名或内容校验失败。请重新从 GitHub Release 下载。"

if [[ ! -d "${INSTALL_ROOT}" ]]; then
  mkdir -p "${INSTALL_ROOT}" 2>/dev/null || true
fi
if [[ ! -w "${INSTALL_ROOT}" ]]; then
  INSTALL_ROOT="${HOME}/Applications"
  mkdir -p "${INSTALL_ROOT}"
  print "系统 Applications 不可写，将安装到：${INSTALL_ROOT}"
fi

TARGET_APP="${INSTALL_ROOT}/Gravtail.app"
TARGET_EXECUTABLE="${TARGET_APP}/Contents/MacOS/HeavyCursor"
gravtail_is_running=0
while IFS= read -r running_command; do
  case "${running_command}" in
    "${TARGET_EXECUTABLE}"|"${TARGET_EXECUTABLE} "*)
      gravtail_is_running=1
      break
      ;;
  esac
done < <(ps -axo command=)
if [[ "${gravtail_is_running}" == "1" ]]; then
  fail "Gravtail 正在运行。请先从顶部菜单选择“退出 Gravtail”，再重新运行安装程序。"
fi

print "1/4  准备这台 Mac 的 Gravtail 本地签名…"
"${SUPPORT_DIR}/ensure-local-signing-identity.sh" "${IDENTITY_NAME}"
IDENTITY_HASH="$(security find-identity -p codesigning -v 2>/dev/null | awk -v name="\"${IDENTITY_NAME}\"" 'index($0, name) { print $2; exit }')"
[[ "${IDENTITY_HASH}" =~ '^[0-9A-Fa-f]{40}$' ]] || fail "无法定位 '${IDENTITY_NAME}' 的证书指纹。"

stage_dir="$(mktemp -d "${INSTALL_ROOT}/.gravtail-install.XXXXXX")"
trap 'rm -rf "${stage_dir}"' EXIT
staged_app="${stage_dir}/Gravtail.app"
backup_app=""

restore_previous_install() {
  if [[ -e "${TARGET_APP}" ]]; then
    mv "${TARGET_APP}" "${stage_dir}/Gravtail.failed.app" 2>/dev/null || true
  fi
  if [[ -n "${backup_app}" && -e "${backup_app}" ]]; then
    mv "${backup_app}" "${TARGET_APP}" || return 1
  fi
}

print "2/4  复制并使用本地身份重新签名…"
ditto "${SOURCE_APP}" "${staged_app}"
codesign --force --deep \
  --sign "${IDENTITY_HASH}" \
  --entitlements "${SUPPORT_DIR}/HeavyCursor.entitlements" \
  "${staged_app}" >/dev/null
codesign --verify --deep --strict "${staged_app}"
codesign --verify --deep --strict \
  -R="certificate leaf = H\"${IDENTITY_HASH}\"" \
  "${staged_app}" >/dev/null

signature_info="$(codesign -d -vv "${staged_app}" 2>&1)"
signer="$(print -r -- "${signature_info}" | awk -F= '/^Authority=/ && !found { print $2; found=1 }')"
[[ "${signer}" == "${IDENTITY_NAME}" ]] || fail "本地重签名校验失败。"

# The user has already explicitly opened this verified installer. Remove only
# the downloaded App's quarantine marker after its incoming signature, bundle
# ID, and new local signature have all passed verification. This avoids a
# second Gatekeeper detour when the installed App is opened for the first time.
xattr -dr com.apple.quarantine "${staged_app}" 2>/dev/null || true

print "3/4  固定安装到：${TARGET_APP}"
if [[ -e "${TARGET_APP}" ]]; then
  backup_app="${INSTALL_ROOT}/Gravtail.previous-$(date +%Y%m%d-%H%M%S)-$$.app"
  mv "${TARGET_APP}" "${backup_app}"
  print "旧版本已保留在：${backup_app}"
fi
if ! mv "${staged_app}" "${TARGET_APP}"; then
  restore_previous_install || true
  fail "新版本无法放入 Applications，已尝试恢复旧版本。"
fi

print "4/4  验证安装结果…"
if ! codesign --verify --deep --strict "${TARGET_APP}"; then
  restore_previous_install || true
  fail "安装后的签名校验失败，已恢复旧版本。"
fi
installed_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${TARGET_APP}/Contents/Info.plist" 2>/dev/null || true)"
if [[ "${installed_bundle_id}" != "${EXPECTED_BUNDLE_ID}" ]]; then
  restore_previous_install || true
  fail "安装后的 Bundle ID 校验失败，已恢复旧版本。"
fi

# Register the fixed install path before launch so Launch Services and TCC see
# the locally signed copy, never the temporary copy inside the download ZIP.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -f "${TARGET_APP}" >/dev/null 2>&1 || true
fi

# Keep one recoverable previous version and discard older installer backups.
# Without this, every update silently leaves another full .app in Applications.
setopt local_options null_glob
previous_apps=("${INSTALL_ROOT}"/Gravtail.previous-*.app(Nom))
if (( ${#previous_apps[@]} > 1 )); then
  for old_app in "${previous_apps[@]:1}"; do
    rm -rf -- "${old_app}"
  done
fi

print ""
print "Gravtail 已安装并绑定到这台 Mac 的本地签名。"
print "现在可以直接打开 Gravtail.app；安装器已验证并移除它的下载隔离标记。"
print "然后在顶部 Gravtail 菜单选择“开启鼠标加重…”，授予一次辅助功能权限。"
print "以后更新请继续运行新版安装包中的此脚本；不要删除钥匙串里的 '${IDENTITY_NAME}'。"

if [[ "${GRAVTAIL_SKIP_LAUNCH:-0}" != "1" ]]; then
  open "${TARGET_APP}"
fi
