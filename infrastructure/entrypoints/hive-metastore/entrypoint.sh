#!/usr/bin/env bash
set -euo pipefail

inspect_schema_state() {
  PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    --host "${POSTGRES_HOST}" \
    --port "${POSTGRES_PORT}" \
    --username "${POSTGRES_USER}" \
    --dbname "${POSTGRES_DB}" \
    --no-password \
    --tuples-only \
    --no-align \
    --set ON_ERROR_STOP=1 \
    --command "SELECT to_regclass('public.\"VERSION\"') IS NOT NULL;"
}

validate_schema() {
  schematool -dbType postgres -validate
}

initialize_schema_if_required() {
  local schema_exists

  echo "Checking the Hive Metastore database schema..."
  if ! schema_exists="$(inspect_schema_state)"; then
    echo "Unable to inspect the Hive Metastore database schema." >&2
    return 1
  fi

  case "${schema_exists}" in
    t)
      validate_schema
      ;;
    f)
      echo "Initializing the Hive Metastore database schema..."
      schematool -dbType postgres -initSchema
      validate_schema
      ;;
    *)
      echo "Unexpected response while inspecting the Hive Metastore schema." >&2
      return 1
      ;;
  esac
}

start_hive_metastore() {
  echo "Starting Hive Metastore..."
  exec hive --service metastore
}

main() {
  initialize_schema_if_required
  start_hive_metastore
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
