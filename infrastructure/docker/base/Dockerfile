FROM eclipse-temurin:8-jdk-jammy@sha256:b5f541356025b22031e2337b72c2d2a511bacf7eb79100acb7f107a06cacc838

ARG BASE_DIR_PATH="/opt"
ARG HADOOP_VERSION="3.3.6"
ARG HIVE_VERSION="3.1.3"
ARG SPARK_VERSION="3.5.5"
ARG JAR_POSTGRES_VERSION="42.7.5"
ARG HADOOP_SHA512="de3eaca2e0517e4b569a88b63c89fae19cb8ac6c01ff990f1ff8f0cc0f3128c8e8a23db01577ca562a0e0bb1b4a3889f8c74384e609cd55e537aada3dcaa9f8a"
ARG SPARK_SHA512="ec5ff678136b1ff981e396d1f7b5dfbf399439c5cb853917e8c954723194857607494a89b7e205fce988ec48b1590b5caeae3b18e1b5db1370c0522b256ff376"
ARG HIVE_SHA256="0c9b6a6359a7341b6029cc9347435ee7b379f93846f779d710b13f795b54bb16"
ARG JAR_POSTGRES_SHA256="69020b3bd20984543e817393f2e6c01a890ef2e37a77dd11d6d8508181d079ab"
ARG USER_HDFS="root"

ARG PATH_HOST_CONFIG_SERVICES_FILES="/infrastructure/configs"
ARG PATH_HOST_CONFIG_NODES_FILES="/infrastructure/entrypoints"

ARG LINK_DOWNLOAD_HADOOP="https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"
ARG LINK_DOWNLOAD_SPARK="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz"
ARG LINK_DOWNLOAD_HIVE="https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz"
ARG LINK_JAR_POSTGRES="https://repo1.maven.org/maven2/org/postgresql/postgresql/${JAR_POSTGRES_VERSION}/postgresql-${JAR_POSTGRES_VERSION}.jar"

ENV HADOOP_HOME="${BASE_DIR_PATH}/hadoop"
ENV SPARK_HOME="${BASE_DIR_PATH}/spark"
ENV HIVE_HOME="${BASE_DIR_PATH}/hive"

ENV HADOOP_CONF_DIR="${BASE_DIR_PATH}/hadoop/etc/hadoop"
ENV YARN_CONF_DIR="${HADOOP_CONF_DIR}"

ENV SPARK_CONF_DIR="${SPARK_HOME}/conf"
ENV HDFS_VERSION="${HADOOP_HOME}/dfs/name/current/VERSION"
ENV HDFS_NAMENODE_USER="${USER_HDFS}"
ENV HDFS_DATANODE_USER="${USER_HDFS}"
ENV HDFS_SECONDARYNAMENODE_USER="${USER_HDFS}"

ENV PATH="${HIVE_HOME}/bin:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${SPARK_HOME}/bin:${PATH}"

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    postgresql-client \
    wget && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${HADOOP_HOME} && \
    mkdir -p ${SPARK_HOME} && \
    mkdir -p ${HIVE_HOME} && \
    wget ${LINK_DOWNLOAD_HADOOP} -O /tmp/hadoop.tar.gz && \
    wget ${LINK_DOWNLOAD_SPARK} -O /tmp/spark.tgz && \
    wget ${LINK_DOWNLOAD_HIVE} -O /tmp/hive.tar.gz && \
    wget ${LINK_JAR_POSTGRES} -O /tmp/postgresql.jar && \
    echo "${HADOOP_SHA512}  /tmp/hadoop.tar.gz" | sha512sum --check --strict - && \
    echo "${SPARK_SHA512}  /tmp/spark.tgz" | sha512sum --check --strict - && \
    echo "${HIVE_SHA256}  /tmp/hive.tar.gz" | sha256sum --check --strict - && \
    echo "${JAR_POSTGRES_SHA256}  /tmp/postgresql.jar" | sha256sum --check --strict - && \
    tar -xvzf /tmp/hadoop.tar.gz -C ${HADOOP_HOME} --strip-components=1 && \
    tar -xvzf /tmp/spark.tgz -C ${SPARK_HOME} --strip-components=1 && \
    tar -xvzf /tmp/hive.tar.gz -C ${HIVE_HOME} --strip-components=1 && \
    mv /tmp/postgresql.jar ${HIVE_HOME}/lib/postgresql-${JAR_POSTGRES_VERSION}.jar && \
    rm /tmp/hadoop.tar.gz /tmp/spark.tgz /tmp/hive.tar.gz

RUN mkdir -p ${HADOOP_HOME}/dfs/data && \
    mkdir -p ${HADOOP_HOME}/dfs/name && \
    mkdir -p /tmp/dir && \
    mkdir -p ${HADOOP_HOME}/logs

RUN echo "export JAVA_HOME=${JAVA_HOME}" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh && \
    echo 'export HADOOP_HOME=$HADOOP_HOME' >> $HIVE_HOME/bin/hive_config.sh


COPY ${PATH_HOST_CONFIG_SERVICES_FILES}/*/* /tmp/platform-configs/
COPY ${PATH_HOST_CONFIG_NODES_FILES}/ /opt/nodes_files/

RUN cp /tmp/platform-configs/* ${HADOOP_CONF_DIR}/ && \
    cp /tmp/platform-configs/* ${SPARK_CONF_DIR}/ && \
    rm -r /tmp/platform-configs
