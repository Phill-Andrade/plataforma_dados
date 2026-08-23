#!/usr/bin/env bash
# Shared command assertions. The suite provides pass, fail_test, and last_output.

assert_command_status() {
  # Arguments: assertion name, expected status, command, and command arguments.
  # Captures combined output in the global last_output variable.
  local name="$1"
  local expected_status="$2"
  shift 2

  local actual_status
  last_output="$("$@" 2>&1)"
  actual_status=$?

  if (( actual_status == expected_status )); then
    pass "${name}"
    return
  fi

  fail_test "${name}: expected status ${expected_status}, got ${actual_status}. Output: ${last_output}"
  return 1
}

assert_script_status() {
  # Arguments: assertion name, expected status, script path, and script arguments.
  local name="$1"
  local expected_status="$2"
  local script_path="$3"
  shift 3

  assert_command_status "${name}" "${expected_status}" bash "${script_path}" "$@"
}

assert_last_output_contains() {
  # Arguments: assertion name and text expected in the global last_output value.
  local name="$1"
  local expected_text="$2"

  if [[ "${last_output}" == *"${expected_text}"* ]]; then
    pass "${name}"
    return
  fi

  fail_test "${name}: output does not contain '${expected_text}'. Output: ${last_output}"
  return 1
}
