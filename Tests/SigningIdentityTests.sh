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
print 'SigningIdentityTests passed'
