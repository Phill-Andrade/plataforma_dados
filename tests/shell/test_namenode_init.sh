#!/usr/bin/env bash
# Tests NameNode volume initialization with a temporary fake HDFS command.
# Run: bash tests/shell/test_namenode_init.sh
# Returns 0 when all assertions pass and 1 when any assertion fails.
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
source "${REPO_ROOT}/tests/shell/helpers/temporary_directories.sh"

TEST_TMP_DIR="$(create_test_directory)" || exit 1
readonly TEST_TMP_DIR
readonly NAMENODE_ENTRYPOINT="${REPO_ROOT}/infrastructure/entrypoints/namenode-init/entrypoint.sh"
readonly FAKE_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly VERSION_PATH="${TEST_TMP_DIR}/namenode/current/VERSION"
failures=0
last_output=""

source "${REPO_ROOT}/tests/shell/helpers/assertions.sh"
source "${REPO_ROOT}/tests/shell/helpers/command_assertions.sh"

# Test infrastructure

cleanup() {
  remove_test_directory "${TEST_TMP_DIR}"
}

prepare_fake_hdfs() {
  # Replaces hdfs through PATH and prints the arguments it receives.
  mkdir -p "${FAKE_BIN_DIR}" "$(dirname "${VERSION_PATH}")"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "$*"' >"${FAKE_BIN_DIR}/hdfs"
  chmod +x "${FAKE_BIN_DIR}/hdfs"
}

# Test cases

test_requires_version_path() {
  assert_command_status \
    "NameNode bootstrap requires the version path" 1 \
    env -u HDFS_VERSION bash "${NAMENODE_ENTRYPOINT}"
}

test_formats_empty_volume() {
  assert_command_status \
    "NameNode bootstrap formats an empty volume" 0 \
    env HDFS_VERSION="${VERSION_PATH}" PATH="${FAKE_BIN_DIR}:${PATH}" \
    bash "${NAMENODE_ENTRYPOINT}" || return
  assert_last_output_contains \
    "NameNode bootstrap invokes non-interactive formatting" \
    "namenode -format -force -nonInteractive"
}

test_preserves_formatted_volume() {
  touch "${VERSION_PATH}"
  assert_command_status \
    "NameNode bootstrap preserves a formatted volume" 0 \
    env HDFS_VERSION="${VERSION_PATH}" PATH="${FAKE_BIN_DIR}:${PATH}" \
    bash "${NAMENODE_ENTRYPOINT}" || return
  assert_last_output_contains \
    "NameNode bootstrap reports the existing format" \
    "already formatted"
}

# Test runner

main() {
  trap cleanup EXIT
  prepare_fake_hdfs
  test_requires_version_path
  test_formats_empty_volume
  test_preserves_formatted_volume
  finish_tests "NameNode bootstrap"
}

main
