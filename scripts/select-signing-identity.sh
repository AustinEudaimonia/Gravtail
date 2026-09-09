#!/bin/zsh
set -euo pipefail

# Read security find-identity output; prefer the installed app's exact leaf.
# Certificate display names are not stable cryptographic identities.
identity_name="${1:?identity name required}"
expected_hash="${2:-}"
awk -v name="\"${identity_name}\"" -v expected="${expected_hash}" '
  length($2) == 40 && $2 ~ /^[0-9a-fA-F]+$/ {
    hash = toupper($2)
    if (expected != "" ? hash == toupper(expected) : index($0, name) > 0) {
      if (!seen[hash]++) { count++; selected = hash }
    }
  }
  END {
    if (count == 1) { print selected; exit 0 }
    if (count > 1) print "发现多个同名签名证书，拒绝随机选择。请保留并明确原有证书。" > "/dev/stderr"
    else print "未找到所需的有效签名证书和私钥。请解锁钥匙串，或恢复原证书及私钥；不会自动更换身份。" > "/dev/stderr"
    exit 1
  }
'
