#!/usr/bin/env bash
set -euo pipefail

readonly VERSION_PATH="${HDFS_VERSION:?HDFS_VERSION is required}"

format_namenode_if_required() {
  if [[ -f "${VERSION_PATH}" ]]; then
    echo "NameNode is already formatted."
    return
  fi

  echo "Formatting NameNode for the first time..."
  hdfs namenode -format -force -nonInteractive
}

main() {
  format_namenode_if_required
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
