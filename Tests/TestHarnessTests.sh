#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
test_harness="${project_dir}/test.sh"

grep -q 'GRAVTAIL_INSTALLER_ARCHIVE' "${test_harness}" || {
  print -u2 'FAIL: test.sh must accept an explicit installer archive'
  exit 1
}
grep -q 'InstallerIntegrationTests.sh' "${test_harness}" || {
  print -u2 'FAIL: test.sh must run installer integration tests'
  exit 1
}
grep -q 'Gravtail-.*-macOS.zip' "${test_harness}" || {
  print -u2 'FAIL: test.sh must discover a local macOS package archive'
  exit 1
}

print 'TestHarnessTests passed'
