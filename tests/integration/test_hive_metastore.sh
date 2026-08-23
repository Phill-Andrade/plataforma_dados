#!/usr/bin/env bash
# Tests schema validation and catalog operations against the running platform.
# Run: bash tests/integration/test_hive_metastore.sh
# Returns 0 when all assertions pass and 1 when setup or an assertion fails.
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
readonly COMPOSE_PATH="${REPO_ROOT}/infrastructure/compose/compose.yaml"
readonly TEST_DATABASE="platform_smoke_${$}_$(date +%s)"
readonly TEST_TABLE="metastore_probe"
readonly COMPOSE=(
  docker compose
  -f "${COMPOSE_PATH}"
)
failures=0
last_output=""

source "${REPO_ROOT}/tests/shell/helpers/assertions.sh"
source "${REPO_ROOT}/tests/shell/helpers/command_assertions.sh"

# Test infrastructure

hive_metastore_is_healthy() {
  # Returns 0 only when Compose resolves a healthy Metastore container.
  local container_id

  container_id="$("${COMPOSE[@]}" ps -q hive-metastore)" || return 1
  [[ -n "${container_id}" ]] || return 1
  [[ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${container_id}")" == "healthy" ]]
}

require_healthy_hive_metastore() {
  if hive_metastore_is_healthy; then
    return
  fi

  echo "Hive Metastore is not healthy. Start the platform with ./scripts/start-platform.sh." >&2
  return 1
}

cleanup_test_database() {
  # Removes the temporary catalog database without replacing the test result.
  "${COMPOSE[@]}" exec -T hive-metastore \
    hive -S -e "DROP DATABASE IF EXISTS ${TEST_DATABASE} CASCADE;" \
    >/dev/null 2>&1 || true
}

assert_catalog_schema() {
  # Reads last_output and verifies the columns returned by Hive DESCRIBE.
  if grep -Eq '^id[[:space:]]+int[[:space:]]*$' <<<"${last_output}" &&
    grep -Eq '^label[[:space:]]+string[[:space:]]*$' <<<"${last_output}"; then
    pass "Hive DESCRIBE returns the registered table schema"
    return
  fi

  fail_test "Hive DESCRIBE did not return the expected schema: ${last_output}"
}

# Test cases

test_metastore_schema() {
  assert_command_status \
    "Metastore schema is valid" 0 \
    "${COMPOSE[@]}" exec -T hive-metastore schematool -dbType postgres -validate
}

test_catalog_operations() {
  local query="
    CREATE DATABASE ${TEST_DATABASE};
    CREATE TABLE ${TEST_DATABASE}.${TEST_TABLE} (id INT, label STRING);
    SHOW TABLES IN ${TEST_DATABASE};
    DESCRIBE ${TEST_DATABASE}.${TEST_TABLE};
  "

  assert_command_status \
    "Hive creates and queries a temporary Metastore table" 0 \
    "${COMPOSE[@]}" exec -T hive-metastore hive -S -e "${query}" || return
  assert_last_output_contains "Hive SHOW TABLES returns the registered table" "${TEST_TABLE}"
  assert_catalog_schema
}

# Test runner

main() {
  require_healthy_hive_metastore || return 1
  trap cleanup_test_database EXIT

  test_metastore_schema && test_catalog_operations
  finish_tests "Hive integration"
}

main
