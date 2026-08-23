#!/usr/bin/env bash
# Tests the Hive schema bootstrap with temporary fake commands.
# Run: bash tests/shell/test_hive_bootstrap.sh
# Returns 0 when all assertions pass and 1 when any assertion fails.
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
source "${REPO_ROOT}/tests/shell/helpers/temporary_directories.sh"

TEST_TMP_DIR="$(create_test_directory)" || exit 1
readonly TEST_TMP_DIR
readonly FAKE_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly CALL_LOG="${TEST_TMP_DIR}/schematool-calls.log"
failures=0
last_output=""

source "${REPO_ROOT}/tests/shell/helpers/assertions.sh"
source "${REPO_ROOT}/tests/shell/helpers/command_assertions.sh"

# Test infrastructure

cleanup() {
  remove_test_directory "${TEST_TMP_DIR}"
}

run_bootstrap() {
  # Arguments: schema state and optional schematool validation status.
  # Updates last_output and returns the bootstrap status.
  local schema_state="$1"
  local schema_validation_status="${2:-0}"
  local actual_status

  true >"${CALL_LOG}"
  last_output="$(
    export PATH="${FAKE_BIN_DIR}:${PATH}"
    export POSTGRES_HOST=postgres
    export POSTGRES_PORT=5432
    export POSTGRES_DB=postgres
    export POSTGRES_USER=postgres
    export POSTGRES_PASSWORD=test-password
    export SCHEMA_STATE="${schema_state}"
    export SCHEMA_VALIDATION_STATUS="${schema_validation_status}"
    export CALL_LOG

    bash -c 'source "$1"; initialize_schema_if_required' _ \
      "${REPO_ROOT}/infrastructure/entrypoints/hive-metastore/entrypoint.sh" 2>&1
  )"
  actual_status=$?
  return "${actual_status}"
}

assert_status() {
  # Arguments: assertion name, expected status, and actual status.
  local name="$1"
  local expected_status="$2"
  local actual_status="$3"

  if (( actual_status == expected_status )); then
    pass "${name}"
    return
  fi

  fail_test "${name}: expected status ${expected_status}, got ${actual_status}. Output: ${last_output}"
}

assert_calls() {
  # Arguments: assertion name and expected schematool call log.
  local name="$1"
  local expected="$2"
  local actual
  actual="$(<"${CALL_LOG}")"

  if [[ "${actual}" == "${expected}" ]]; then
    pass "${name}"
    return
  fi

  fail_test "${name}: expected calls '${expected}', got '${actual}'."
}

create_fake_psql() {
  # Simulates whether the Hive schema exists or the database is inaccessible.
  cat >"${FAKE_BIN_DIR}/psql" <<'EOF_PSQL'
#!/usr/bin/env bash
case "${SCHEMA_STATE}" in
  present) echo t ;;
  absent) echo f ;;
  inaccessible)
    echo "password authentication failed" >&2
    exit 2
    ;;
  *) echo unexpected ;;
esac
EOF_PSQL
}

create_fake_schematool() {
  # Records schema initialization and validation without invoking Hive.
  cat >"${FAKE_BIN_DIR}/schematool" <<'EOF_SCHEMATOOL'
#!/usr/bin/env bash
if [[ "$*" == *-initSchema* ]]; then
  echo init >>"${CALL_LOG}"
  exit 0
fi

echo validate >>"${CALL_LOG}"
exit "${SCHEMA_VALIDATION_STATUS}"
EOF_SCHEMATOOL
}

create_fake_hive() {
  # Exposes the arguments that would start the real Hive service.
  cat >"${FAKE_BIN_DIR}/hive" <<'EOF_HIVE'
#!/usr/bin/env bash
echo "$*"
EOF_HIVE
}

prepare_fake_commands() {
  mkdir -p "${FAKE_BIN_DIR}"
  create_fake_psql
  create_fake_schematool
  create_fake_hive
  chmod +x "${FAKE_BIN_DIR}/psql" "${FAKE_BIN_DIR}/schematool" "${FAKE_BIN_DIR}/hive"
}

assert_bootstrap_scenario() {
  # Arguments: scenario, schema state, expected status, expected calls,
  # and optional schematool validation status.
  local scenario="$1"
  local schema_state="$2"
  local expected_status="$3"
  local expected_calls="$4"
  local schema_validation_status="${5:-0}"
  local actual_status

  run_bootstrap "${schema_state}" "${schema_validation_status}"
  actual_status=$?
  assert_status "${scenario} returns the expected status" "${expected_status}" "${actual_status}"
  assert_calls "${scenario} uses the expected schema commands" "${expected_calls}"
}

# Test cases

test_existing_schema() {
  assert_bootstrap_scenario "existing schema" present 0 validate
}

test_missing_schema() {
  assert_bootstrap_scenario "missing schema" absent 0 $'init\nvalidate'
}

test_database_access_failure() {
  assert_bootstrap_scenario "database access failure" inaccessible 1 ""
}

test_invalid_existing_schema() {
  assert_bootstrap_scenario "invalid existing schema" present 3 validate 3
}

test_metastore_start() {
  local actual_status

  last_output="$(
    env PATH="${FAKE_BIN_DIR}:${PATH}" \
      bash -c 'source "$1"; start_hive_metastore' _ \
      "${REPO_ROOT}/infrastructure/entrypoints/hive-metastore/entrypoint.sh" \
      2>&1
  )"
  actual_status=$?

  assert_status "Hive bootstrap starts the Metastore service" 0 "${actual_status}"
  (( actual_status == 0 )) || return
  assert_last_output_contains "Hive bootstrap uses the Metastore service command" "--service metastore"
}

# Test runner

main() {
  trap cleanup EXIT
  prepare_fake_commands
  test_existing_schema
  test_missing_schema
  test_database_access_failure
  test_invalid_existing_schema
  test_metastore_start
  finish_tests "Hive bootstrap"
}

main
