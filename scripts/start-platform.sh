#!/usr/bin/env bash
#
# Public entry point for the Hadoop platform lifecycle. Starts the complete
# platform, stops it with --down, and delegates worker scaling requests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"
COMPOSE_PATH="${REPO_ROOT}/infrastructure/compose/compose.yaml"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--down | -w NUMBER]

Options:
  -w, --worker, --workers NUMBER
                        Scale DataNode and NodeManager to the requested number of replicas.
  --down                Stop and remove the platform containers and network.
  -h, --help            Show this help message.

Examples:
  $(basename "$0")
  $(basename "$0") -w 3
  $(basename "$0") --down
USAGE
}

usage_error() {
  echo "[ERROR] Invalid arguments." >&2
  usage >&2
  return 2
}

main() {
  if (( $# == 0 )); then
    exec docker compose -f "${COMPOSE_PATH}" up --build
  fi

  case "$1" in
    -h|--help)
      (( $# == 1 )) || usage_error
      usage
      ;;
    --down)
      (( $# == 1 )) || usage_error
      exec docker compose -f "${COMPOSE_PATH}" down
      ;;
    -w|--worker|--workers)
      exec "${SCRIPT_DIR}/scale-workers.sh" "$@"
      ;;
    *)
      usage_error
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
