#!/usr/bin/env bash
# Tests platform lifecycle delegation with a temporary fake Docker command.
# Run: bash tests/shell/test_start_platform.sh
# Returns 0 when all assertions pass and 1 when any assertion fails.
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
source "${REPO_ROOT}/tests/shell/helpers/temporary_directories.sh"

TEST_TMP_DIR="$(create_test_directory)" || exit 1
readonly TEST_TMP_DIR
readonly START_PLATFORM_SCRIPT="${REPO_ROOT}/scripts/start-platform.sh"
readonly FAKE_BIN_DIR="${TEST_TMP_DIR}/bin"
failures=0
last_output=""

source "${REPO_ROOT}/tests/shell/helpers/assertions.sh"
source "${REPO_ROOT}/tests/shell/helpers/command_assertions.sh"

# Test infrastructure

cleanup() {
  remove_test_directory "${TEST_TMP_DIR}"
}

prepare_fake_docker() {
  # Exports a PATH that intercepts Docker calls and prints their arguments.
  mkdir -p "${FAKE_BIN_DIR}"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "$*"' >"${FAKE_BIN_DIR}/docker"
  chmod +x "${FAKE_BIN_DIR}/docker"
  export PATH="${FAKE_BIN_DIR}:${PATH}"
}

# Test cases

test_invalid_arguments() {
  assert_script_status "start rejects unknown actions" 2 "${START_PLATFORM_SCRIPT}" --unknown
  assert_script_status "start rejects arguments after down" 2 "${START_PLATFORM_SCRIPT}" --down unexpected
}

test_help() {
  assert_script_status "start shows help" 0 "${START_PLATFORM_SCRIPT}" --help
}

test_platform_start() {
  assert_script_status "start delegates build and startup to Compose" 0 "${START_PLATFORM_SCRIPT}"
  assert_last_output_contains "start requests the shared image build" "up --build"
}

test_platform_shutdown() {
  assert_script_status "down delegates shutdown to Compose" 0 "${START_PLATFORM_SCRIPT}" --down
  assert_last_output_contains "down requests the platform shutdown" "down"
}

test_worker_scaling() {
  assert_script_status "start delegates worker scaling" 0 "${START_PLATFORM_SCRIPT}" --workers 4
  assert_last_output_contains "worker delegation preserves the requested count" "--scale datanode=4"
}

# Test runner

main() {
  trap cleanup EXIT
  prepare_fake_docker
  test_invalid_arguments
  test_help
  test_platform_start
  test_platform_shutdown
  test_worker_scaling
  finish_tests "platform lifecycle"
}

main
