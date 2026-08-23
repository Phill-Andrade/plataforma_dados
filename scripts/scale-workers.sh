#!/usr/bin/env bash
#
# Validates and scales DataNode and NodeManager replicas together.
# start-platform.sh delegates worker topology changes to this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"
COMPOSE_PATH="${REPO_ROOT}/infrastructure/compose/compose.yaml"

usage() {
  echo "Usage: $(basename "$0") -w NUMBER"
}

fail() {
  echo "[ERROR] $1" >&2
  return 2
}

validate_worker_count() {
  local value="$1"

  if ! [[ "${value}" =~ ^[1-9][0-9]*$ ]]; then
    fail "The worker count must be a positive integer."
  fi

  if (( value < 1 || value > 12 )); then
    fail "The worker count must be between 1 and 12."
  fi
}

main() {
  if (( $# != 2 )); then
    usage >&2
    fail "Expected a worker option followed by the number of workers."
  fi

  case "$1" in
    -w|--worker|--workers)
      ;;
    *)
      usage >&2
      fail "Unknown argument: $1"
      ;;
  esac

  local workers="$2"
  validate_worker_count "${workers}"

  if (( workers < 2 )); then
    echo "[WARNING] HDFS replication is 2; blocks may remain" \
      "under-replicated with ${workers} worker(s)." >&2
  fi

  echo "Scaling DataNode and NodeManager to ${workers} worker(s)..."
  # Reconcile only worker daemons; preserve existing replicas and dependencies.
  exec docker compose -f "${COMPOSE_PATH}" up -d \
    --no-deps \
    --no-recreate \
    --scale "datanode=${workers}" \
    --scale "nodemanager=${workers}" \
    datanode nodemanager
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
