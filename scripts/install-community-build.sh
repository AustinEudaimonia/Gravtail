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
if ps -axo command= | grep -F "${TARGET_EXECUTABLE}" | grep -v grep >/dev/null 2>&1; then
  fail "Gravtail 正在运行。请先从顶部菜单选择“退出 Gravtail”，再重新运行安装程序。"
fi

print "1/4  准备这台 Mac 的 Gravtail 本地签名…"
"${SUPPORT_DIR}/ensure-local-signing-identity.sh" "${IDENTITY_NAME}"

stage_dir="$(mktemp -d "${INSTALL_ROOT}/.gravtail-install.XXXXXX")"
trap 'rm -rf "${stage_dir}"' EXIT
staged_app="${stage_dir}/Gravtail.app"

print "2/4  复制并使用本地身份重新签名…"
ditto "${SOURCE_APP}" "${staged_app}"
codesign --force --deep \
  --sign "${IDENTITY_NAME}" \
  --entitlements "${SUPPORT_DIR}/HeavyCursor.entitlements" \
  "${staged_app}" >/dev/null
codesign --verify --deep --strict "${staged_app}"

signature_info="$(codesign -d -vv "${staged_app}" 2>&1)"
signer="$(print -r -- "${signature_info}" | awk -F= '/^Authority=/ && !found { print $2; found=1 }')"
[[ "${signer}" == "${IDENTITY_NAME}" ]] || fail "本地重签名校验失败。"

print "3/4  固定安装到：${TARGET_APP}"
if [[ -e "${TARGET_APP}" ]]; then
  backup_app="${INSTALL_ROOT}/Gravtail.previous-$(date +%Y%m%d-%H%M%S)-$$.app"
  mv "${TARGET_APP}" "${backup_app}"
  print "旧版本已保留在：${backup_app}"
fi
mv "${staged_app}" "${TARGET_APP}"

print "4/4  验证安装结果…"
codesign --verify --deep --strict "${TARGET_APP}"
installed_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${TARGET_APP}/Contents/Info.plist")"
[[ "${installed_bundle_id}" == "${EXPECTED_BUNDLE_ID}" ]] || fail "安装后的 Bundle ID 校验失败。"

print ""
print "Gravtail 已安装并绑定到这台 Mac 的本地签名。"
print "首次打开：按住 Control 点击 Gravtail.app → 打开。"
print "然后在顶部 Gravtail 菜单选择“开启鼠标加重…”，授予一次辅助功能权限。"
print "以后更新请继续运行新版安装包中的此脚本；不要删除钥匙串里的 '${IDENTITY_NAME}'。"

if [[ "${GRAVTAIL_SKIP_LAUNCH:-0}" != "1" ]]; then
  open "${TARGET_APP}"
fi
