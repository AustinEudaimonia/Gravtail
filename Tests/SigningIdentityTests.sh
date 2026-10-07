#!/bin/zsh
set -euo pipefail
selector="${0:A:h:h}/scripts/select-signing-identity.sh"
first_hash="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
second_hash="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
identities="1) ${first_hash} \"Gravtail Local\"
2) ${second_hash} \"Gravtail Local\""
selected="$(print -r -- "${identities}" | zsh "${selector}" 'Gravtail Local' "${second_hash}")"
[[ "${selected}" == "${second_hash}" ]]
if print -r -- "${identities}" | zsh "${selector}" 'Gravtail Local' >/dev/null 2>&1; then
  print -u2 'FAIL: ambiguous first-install identity accepted'; exit 1
fi
if print -r -- "1) ${first_hash} \"Gravtail Local\"" | zsh "${selector}" 'Gravtail Local' "${second_hash}" >/dev/null 2>&1; then
  print -u2 'FAIL: missing original identity silently replaced'; exit 1
fi
selected="$(print -r -- "1) ${first_hash} \"Heavy Cursor Local\"" | zsh "${selector}" 'Gravtail Local' "${first_hash}")"
[[ "${selected}" == "${first_hash}" ]]
selected="$(print -r -- "1) ${first_hash} \"Gravtail Local\"" | zsh "${selector}" 'Gravtail Local')"
[[ "${selected}" == "${first_hash}" ]]

# Existing identities must still repair code-signing trust. This exercises the
# branch used on updates, not only the first-time certificate creation path.
trust_test_dir="$(mktemp -d -t gravtail-signing-trust-test)"
trap 'rm -rf "${trust_test_dir}"' EXIT
mock_bin="${trust_test_dir}/bin"
mkdir -p "${mock_bin}"
state_file="${trust_test_dir}/verify-count"
marker_file="${trust_test_dir}/trust-repaired"
cat >"${mock_bin}/security" <<'MOCK_SECURITY'
#!/bin/zsh
set -euo pipefail
state_file="${GRAVTAIL_TEST_STATE:?}"
marker_file="${GRAVTAIL_TEST_MARKER:?}"
case "${1:-}" in
  default-keychain)
    print '"/tmp/login.keychain-db"'
    ;;
  find-identity)
    print '1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Gravtail Local"'
    ;;
  find-certificate)
    has_p=0
    for arg in "$@"; do
      [[ "$arg" == "-p" ]] && has_p=1
    done
    if (( has_p )); then
      print -r -- '-----BEGIN CERTIFICATE-----'
      print -r -- 'test-certificate'
      print -r -- '-----END CERTIFICATE-----'
    fi
    ;;
  verify-cert)
    count=0
    [[ -f "${state_file}" ]] && count="$(<"${state_file}")"
    count=$((count + 1))
    print -r -- "${count}" >"${state_file}"
    (( count > 1 ))
    ;;
  add-trusted-cert)
    : >"${marker_file}"
    ;;
esac
MOCK_SECURITY
chmod +x "${mock_bin}/security"
PATH="${mock_bin}:${PATH}" \
GRAVTAIL_TEST_STATE="${state_file}" \
GRAVTAIL_TEST_MARKER="${marker_file}" \
  zsh "${0:A:h:h}/scripts/ensure-local-signing-identity.sh" 'Gravtail Local' >/dev/null
[[ -f "${marker_file}" ]] || {
  print -u2 'FAIL: existing identity did not repair code-signing trust'
  exit 1
}
print 'SigningIdentityTests passed'
