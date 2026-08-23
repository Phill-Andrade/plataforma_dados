#!/usr/bin/env bash
# Shared assertion reporting. The calling suite owns the failures counter.

pass() {
  echo "PASS: $1"
}

fail_test() {
  # Prints the failure and increments the global failures counter.
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

finish_tests() {
  # Argument: suite name. Returns 1 when the suite recorded any failure.
  local suite_name="$1"

  if (( failures > 0 )); then
    echo "${failures} ${suite_name} test(s) failed." >&2
    return 1
  fi

  echo "All ${suite_name} tests passed."
}
