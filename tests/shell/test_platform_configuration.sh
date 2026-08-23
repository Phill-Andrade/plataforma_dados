#!/usr/bin/env bash
# Statically verifies the contracts shared by Compose, Docker, Spark, and Hadoop.
# Run: bash tests/shell/test_platform_configuration.sh
# Returns 0 when all assertions pass and 1 when any assertion fails.
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
readonly COMPOSE_PATH="${REPO_ROOT}/infrastructure/compose/compose.yaml"
readonly DOCKERFILE_PATH="${REPO_ROOT}/infrastructure/docker/base/Dockerfile"
readonly HDFS_INIT_ENTRYPOINT="${REPO_ROOT}/infrastructure/entrypoints/hdfs-init/entrypoint.sh"
readonly HDFS_CONFIG_PATH="${REPO_ROOT}/infrastructure/configs/hdfs/hdfs-site.xml"
readonly SPARK_CONFIG_PATH="${REPO_ROOT}/infrastructure/configs/spark/spark-defaults.conf"
readonly YARN_CONFIG_PATH="${REPO_ROOT}/infrastructure/configs/yarn/yarn-site.xml"
failures=0

source "${REPO_ROOT}/tests/shell/helpers/assertions.sh"

# Test infrastructure

assert_true() {
  # Arguments: assertion name followed by a predicate command and its arguments.
  local name="$1"
  shift

  if "$@"; then
    pass "${name}"
    return
  fi

  fail_test "${name}"
  return 1
}

hdfs_topology_is_native() {
  grep -A1 -F "<name>dfs.replication</name>" "${HDFS_CONFIG_PATH}" |
    grep -Fq "<value>2</value>" &&
    grep -A1 -F "<name>dfs.namenode.safemode.min.datanodes</name>" "${HDFS_CONFIG_PATH}" |
      grep -Fq "<value>2</value>"
}

hdfs_initialization_publishes_spark_archive() {
  grep -Fq 'entrypoint: ["bash", "/opt/nodes_files/hdfs-init/entrypoint.sh"]' "${COMPOSE_PATH}" &&
    grep -Fq 'hdfs dfs -mkdir -p /spark_events /lakehouse /yarn_logs "${SPARK_ARCHIVE_DIRECTORY}"' "${HDFS_INIT_ENTRYPOINT}" &&
    grep -Fq 'hdfs dfs -put "${temporary_archive}" "${archive_path}"' "${HDFS_INIT_ENTRYPOINT}"
}

hadoop_anchor_has_no_runtime_environment_file() {
  ! sed -n "/^x-hadoop-service:/,/^services:/p" "${COMPOSE_PATH}" |
    grep -q "env_file:"
}

spark_defaults_do_not_repeat_native_configuration() {
  ! grep -Eq \
    '^(spark\.ui\.enabled|spark\.ui\.port|spark\.history\.ui\.port|spark\.hadoop\.fs\.defaultFS|spark\.hadoop\.yarn\.resourcemanager\.hostname)[[:space:]]' \
    "${SPARK_CONFIG_PATH}"
}

spark_default_is() {
  # Arguments: Spark property name and its expected value.
  local property_name="$1"
  local expected_value="$2"

  awk -v property_name="${property_name}" -v expected_value="${expected_value}" \
    '$1 == property_name && $2 == expected_value { found = 1 } END { exit !found }' \
    "${SPARK_CONFIG_PATH}"
}

spark_defaults_configure_platform() {
  spark_default_is spark.master yarn &&
    spark_default_is spark.submit.deployMode cluster &&
    spark_default_is spark.yarn.archive hdfs://namenode:9000/spark/spark-libs-3.5.5.zip &&
    spark_default_is spark.eventLog.enabled true &&
    spark_default_is spark.eventLog.dir hdfs://namenode:9000/spark_events &&
    spark_default_is spark.history.fs.logDirectory hdfs://namenode:9000/spark_events &&
    spark_default_is spark.sql.warehouse.dir hdfs://namenode:9000/lakehouse &&
    spark_default_is spark.sql.catalogImplementation hive &&
    spark_default_is spark.sql.hive.metastore.jars maven &&
    spark_default_is spark.sql.hive.metastore.version 3.1.3
}

yarn_aggregates_application_logs() {
  grep -A1 -F "<name>yarn.log-aggregation-enable</name>" "${YARN_CONFIG_PATH}" |
    grep -Fq "<value>true</value>" &&
    grep -A1 -F "<name>yarn.nodemanager.remote-app-log-dir</name>" "${YARN_CONFIG_PATH}" |
      grep -Fq "<value>/yarn_logs</value>" &&
    grep -A1 -F "<name>yarn.log-aggregation.retain-seconds</name>" "${YARN_CONFIG_PATH}" |
      grep -Fq "<value>604800</value>"
}

worker_port_ranges_are_literal() {
  grep -Fq '"8042-8053:8042"' "${COMPOSE_PATH}" &&
    grep -Fq '"19864-19875:9864"' "${COMPOSE_PATH}"
}

worker_daemon_healthchecks_use_local_ports() {
  grep -Fq "0.0.0.0:8042" "${YARN_CONFIG_PATH}" &&
    grep -Fq "/dev/tcp/127.0.0.1/9864" "${COMPOSE_PATH}" &&
    grep -Fq "/dev/tcp/127.0.0.1/8042" "${COMPOSE_PATH}"
}

initial_worker_replicas_are_literal() {
  [[ "$(grep -c "replicas: 2" "${COMPOSE_PATH}")" == 2 ]]
}

hadoop_daemons_are_independent_services() {
  grep -Fq 'command: ["hdfs", "namenode"]' "${COMPOSE_PATH}" &&
    grep -Fq 'command: ["yarn", "resourcemanager"]' "${COMPOSE_PATH}" &&
    grep -Fq 'command: ["hdfs", "datanode"]' "${COMPOSE_PATH}" &&
    grep -Fq 'command: ["yarn", "nodemanager"]' "${COMPOSE_PATH}"
}

dockerfile_has_digest_default() {
  # Arguments: Dockerfile ARG name and expected hexadecimal digest length.
  local argument_name="$1"
  local expected_length="$2"
  grep -Eq "^ARG ${argument_name}=\"[0-9a-f]{${expected_length}}\"$" "${DOCKERFILE_PATH}"
}

# Test cases

test_hdfs_configuration() {
  assert_true "HDFS topology is configured natively" hdfs_topology_is_native
  assert_true "HDFS initialization publishes the Spark archive" hdfs_initialization_publishes_spark_archive
}

test_spark_configuration() {
  assert_true "Spark defaults do not repeat native configuration" spark_defaults_do_not_repeat_native_configuration
  assert_true "Spark defaults configure the platform runtime" spark_defaults_configure_platform
}

test_yarn_configuration() {
  assert_true "YARN aggregates application logs in HDFS" yarn_aggregates_application_logs
}

test_worker_configuration() {
  assert_true "worker host-port ranges are fixed in Compose" worker_port_ranges_are_literal
  assert_true "worker daemon healthchecks use local service ports" worker_daemon_healthchecks_use_local_ports
  assert_true "initial worker replicas are fixed in Compose" initial_worker_replicas_are_literal
  assert_true "Hadoop daemons are independent services" hadoop_daemons_are_independent_services
}

test_docker_image_contract() {
  assert_true "Hadoop SHA-512 default is valid" dockerfile_has_digest_default HADOOP_SHA512 128
  assert_true "Spark SHA-512 default is valid" dockerfile_has_digest_default SPARK_SHA512 128
  assert_true "Hive SHA-256 default is valid" dockerfile_has_digest_default HIVE_SHA256 64
  assert_true "PostgreSQL JDBC SHA-256 default is valid" dockerfile_has_digest_default JAR_POSTGRES_SHA256 64
  assert_true \
    "Temurin base image is pinned by digest" \
    bash -c 'grep -Eq "^FROM [^[:space:]@]+@sha256:[0-9a-f]{64}$" "$1"' _ \
    "${DOCKERFILE_PATH}"
  assert_true \
    "Dockerfile does not own the HDFS topology" \
    bash -c '! grep -q "ARG HDFS_REPLICATION" "$1"' _ "${DOCKERFILE_PATH}"
  assert_true \
    "Dockerfile enforces both checksum algorithms" \
    bash -c 'grep -q "sha512sum --check --strict" "$1" && grep -q "sha256sum --check --strict" "$1"' _ \
    "${DOCKERFILE_PATH}"
}

test_compose_contract() {
  assert_true "Compose configuration is valid" docker compose -f "${COMPOSE_PATH}" config --quiet
  assert_true \
    "shared Hadoop anchor owns the image build" \
    bash -c 'sed -n "/^x-hadoop-service:/,/^services:/p" "$1" | grep -q "^  build:"' _ "${COMPOSE_PATH}"
  assert_true "shared Hadoop anchor has no runtime environment file" hadoop_anchor_has_no_runtime_environment_file
}

# Test runner

main() {
  test_hdfs_configuration
  test_spark_configuration
  test_yarn_configuration
  test_worker_configuration
  test_docker_image_contract
  test_compose_contract
  finish_tests "platform configuration"
}

main
