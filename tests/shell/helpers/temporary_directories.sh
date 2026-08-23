#!/usr/bin/env bash
# Creates and safely removes test-owned temporary directories.

create_test_directory() {
  # Prints a unique absolute directory under TMPDIR, or /tmp when unset.
  local temporary_root="${TMPDIR:-/tmp}"
  local directory_path

  if [[ "${temporary_root}" != /* ]]; then
    echo "Test temporary root must be an absolute path: ${temporary_root}" >&2
    return 1
  fi

  directory_path="$(mktemp -d "${temporary_root%/}/platform-data-test.XXXXXX")" || {
    echo "Unable to create the test temporary directory." >&2
    return 1
  }

  printf '%s\n' "${directory_path}"
}

remove_test_directory() {
  # Argument: directory path. Refuses paths outside the test naming contract.
  local directory_path="$1"
  local temporary_root="${TMPDIR:-/tmp}"
  local expected_prefix="${temporary_root%/}/platform-data-test."

  [[ -d "${directory_path}" ]] || return

  if [[ "${directory_path}" != "${expected_prefix}"?????? ]]; then
    echo "Refusing to remove an unexpected test directory: ${directory_path}" >&2
    return 1
  fi

  rm -rf -- "${directory_path}"
}
