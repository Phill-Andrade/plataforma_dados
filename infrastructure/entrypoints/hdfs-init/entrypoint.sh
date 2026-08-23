#!/usr/bin/env bash
set -euo pipefail

readonly SPARK_RELEASE_PATH="${SPARK_HOME:?SPARK_HOME is required}/RELEASE"
readonly SPARK_JARS_PATH="${SPARK_HOME}/jars"
readonly SPARK_ARCHIVE_DIRECTORY="/spark"

create_technical_directories() {
  hdfs dfs -mkdir -p /spark_events /lakehouse /yarn_logs "${SPARK_ARCHIVE_DIRECTORY}"
}

detect_spark_version() {
  local spark_version

  spark_version="$(sed -n 's/^Spark \([^ ]*\).*/\1/p' "${SPARK_RELEASE_PATH}")"
  if [[ -z "${spark_version}" ]]; then
    echo "Unable to detect the installed Spark version." >&2
    return 1
  fi

  printf '%s\n' "${spark_version}"
}

publish_spark_archive() (
  local archive_path="$1"
  local temporary_archive

  temporary_archive="$(mktemp /tmp/spark-libs.XXXXXX)"
  trap 'rm -f -- "${temporary_archive}"' EXIT

  jar cf "${temporary_archive}" -C "${SPARK_JARS_PATH}" .
  hdfs dfs -put "${temporary_archive}" "${archive_path}"
  hdfs dfs -chmod 644 "${archive_path}"
)

ensure_spark_archive() {
  local spark_version
  local archive_path

  spark_version="$(detect_spark_version)"
  archive_path="${SPARK_ARCHIVE_DIRECTORY}/spark-libs-${spark_version}.zip"

  if hdfs dfs -test -e "${archive_path}"; then
    echo "Spark archive already exists at ${archive_path}."
    return
  fi

  echo "Publishing Spark ${spark_version} libraries to ${archive_path}..."
  publish_spark_archive "${archive_path}"
}

main() {
  create_technical_directories
  ensure_spark_archive
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
