#!/usr/bin/env bash
# Tests worker scaling without Docker by placing a fake command first in PATH.
# Run: bash tests/shell/test_scale_workers.sh
# Returns 0 when all assertions pass and 1 when any assertion fails.
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
source "${REPO_ROOT}/tests/shell/helpers/temporary_directories.sh"

TEST_TMP_DIR="$(create_test_directory)" || exit 1
readonly TEST_TMP_DIR
readonly SCALE_WORKERS_SCRIPT="${REPO_ROOT}/scripts/scale-workers.sh"
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

test_invalid_worker_counts() {
  assert_script_status "scale rejects missing arguments" 2 "${SCALE_WORKERS_SCRIPT}"
  assert_script_status "scale rejects a missing worker count" 2 "${SCALE_WORKERS_SCRIPT}" -w
  assert_script_status "scale rejects zero" 2 "${SCALE_WORKERS_SCRIPT}" -w 0
  assert_script_status "scale rejects values above the published port range" 2 "${SCALE_WORKERS_SCRIPT}" -w 13
}

test_valid_worker_count() {
  assert_script_status "scale accepts a valid worker count" 0 "${SCALE_WORKERS_SCRIPT}" --workers 3
  assert_last_output_contains "scale tells Compose the requested DataNode count" "--scale datanode=3"
  assert_last_output_contains "scale tells Compose the requested NodeManager count" "--scale nodemanager=3"
}

test_under_replicated_worker_count() {
  assert_script_status "scale accepts a count below replication with a warning" 0 "${SCALE_WORKERS_SCRIPT}" -w 1
  assert_last_output_contains "scale warns whenever workers are below replication" "under-replicated with 1 worker(s)"
}

# Test runner

main() {
  trap cleanup EXIT
  prepare_fake_docker
  test_invalid_worker_counts
  test_valid_worker_count
  test_under_replicated_worker_count
  finish_tests "worker scaling"
}

main
