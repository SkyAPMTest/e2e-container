# Licensed to the SkyAPM under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/usr/bin/env bash

JAVA_OPTS="${JAVA_OPTS} -Xms256M -Xmx512M"

export SW_HOME=${SW_HOME:-/skywalking}
export ZK_HOME=${ZK_HOME:-/zk}
export ES_HOME=${ES_HOME:-/es}

export OAP_HOME=${OAP_HOME:-.}
export OAP_HOST=${OAP_HOST:-localhost}
export OAP_PORT=${OAP_PORT:-11800}
export SW_CORE_GRPC_HOST=${SW_CORE_GRPC_HOST:-0.0.0.0}
export SW_CORE_GRPC_PORT=${SW_CORE_GRPC_PORT:-11800}
export SW_CORE_REST_HOST=${SW_CORE_REST_HOST:-0.0.0.0}
export SW_CORE_REST_PORT=${SW_CORE_REST_PORT:-12800}

export OAP_LOG_DIR=${OAP_LOG_DIR:-/tmp/logs/oap}

export WEBAPP_HOME=${WEBAPP_HOME:-.}
export WEBAPP_HOST=${WEBAPP_HOST:-localhost}
export WEBAPP_PORT=${WEBAPP_PORT:-8081}
export WEBAPP_LOG_DIR=${WEBAPP_LOG_DIR:-/tmp/logs/webapp}

export AGENT_HOME=${AGENT_HOME:-agent}

export SERVICE_HOME=${SERVICE_HOME:-/home}
export SERVICE_LOG=${SERVICE_LOG:-/tmp/logs/service}

check_tcp() {
    local host=$1
    local port=$2
    local count=$3
    local interval=$4
    local checking_message=$5

    for i in $(seq 1 ${count}); do
        nc -z ${host} ${port}
        if [[ $? -ne 0 ]]; then
            [[ ! -z checking_message ]] && echo ${checking_message}
            sleep 10
        fi
    done

    nc -zv ${host} ${port}
}

start_zk() {
    original_pwd=$(pwd)

    cd ${ZK_HOME}

    tar -zxf apache-zookeeper-3.5.5-bin.tar.gz -C /tmp/ \
        && mv /tmp/apache-zookeeper-3.5.5-bin/* . \
        && cp conf/zoo_sample.cfg conf/zoo.cfg

    bash ${ZK_HOME}/bin/zkServer.sh start 2>&1

    check_tcp localhost 2181 12 10 "waiting for the zookeeper to be ready"

    if [[ $? -ne 0 ]]; then
        echo "zookeeper server failed to start in 120 seconds: "
        cat ${ZK_HOME}/logs/*
        exit 1
    fi

    cd ${original_pwd}
}

start_es() {
    original_pwd=$(pwd)

    cd ${ES_HOME}

    export ES_TMPDIR=`mktemp -d -t elasticsearch.XXXXXXXX`
    export ES_JAVA_OPTS="-Xms1g -Xmx1g"

    addgroup -S es \
        && adduser -S es -G es -s /bin/bash -D \
        && tar -zxf elasticsearch-oss-6.3.2.tar.gz -C /tmp/ \
        && mv /tmp/elasticsearch-6.3.2/* . \
        && chown -R es:es ${ES_HOME} \
        && chown -R es:es /tmp \
        && su es ${ES_HOME}/bin/elasticsearch > logs/stdout.log 2>&1 &

    check_tcp localhost 9200 12 10 "waiting for the elasticsearch to be ready"

    if [[ $? -ne 0 ]]; then
        echo "elasticsearch server failed to start in 120 seconds: "
        cat ${ES_HOME}/logs/elasticsearch.log ${ES_HOME}/logs/stdout.log
        exit 1
    fi

    cd ${original_pwd}
}

start_oap() {
    local mode=$1

    original_pwd=$(pwd)

    cd ${SW_HOME}/

    if test "${mode}" = "init"; then
        bash bin/oapService.sh > /dev/null 2>&1 &
    else
        bash bin/oapServiceNoInit.sh > /dev/null 2>&1 &
    fi
    check_times=30
    check_interval=10

    check_tcp ${SW_CORE_GRPC_HOST} \
              ${SW_CORE_GRPC_PORT} \
              ${check_times} \
              ${check_interval} \
              "waiting for the oap server to be ready"

    if [[ $? -ne 0 ]]; then
        echo "oap server failed to start in ${check_times} * ${check_interval} seconds: "
        cat ${OAP_LOG_DIR}/*
        exit 1
    fi

    echo "oap server is ready for connections"

    cd ${original_pwd}
}

start_webapp() {
    original_pwd=$(pwd)

    cd ${SW_HOME}/

    bash bin/webappService.sh > /dev/null 2>&1 &
    check_tcp ${WEBAPP_HOST} \
          ${WEBAPP_PORT} \
          ${check_times} \
          ${check_interval} \
          "waiting for the web app to be ready"

    if [[ $? -ne 0 ]]; then
        echo "web app failed to start in ${check_times} * ${check_interval} seconds"
        cat ${WEBAPP_LOG_DIR}/*
        exit 1
    fi

    echo "web app is ready for connections"

    cd ${original_pwd}
}

export MODE=${MODE:-standalone}

echo "starting e2e container in mode: ${MODE}"

if test "${MODE}" = "cluster"; then
    start_zk
    start_es

    # substitute application.yml to be capable of cluster mode
    cd ${SW_HOME}/config \
        && awk -f /clusterize.awk application.yml > clusterized_app.yml \
        && mv clusterized_app.yml application.yml

    cd ${SW_HOME}/webapp \
        && awk '/^\s+listOfServers/ {gsub("127.0.0.1:12800", "127.0.0.1:12800,127.0.0.1:12801", $0)} {print}' webapp.yml > clusterized_webapp.yml \
        && mv clusterized_webapp.yml webapp.yml
fi

cd ${SW_HOME}/

mkdir -p ${OAP_LOG_DIR}
mkdir -p ${WEBAPP_LOG_DIR}
mkdir -p ${SERVICE_LOG}

echo 'starting OAP server...' && start_oap 'init'
echo 'starting Web App...' \
    && export SPRING_APPLICATION_JSON='{"server.port":8081}' \
    && WEBAPP_PORT=8081 \
    && start_webapp

if test "${MODE}" = "cluster"; then
    # start another OAP server in a different port
    export SW_CORE_GRPC_PORT=11801 \
        && export SW_CORE_REST_PORT=12801 \
        && start_oap 'no-init'
    unset SW_CORE_GRPC_PORT SW_CORE_REST_PORT

    # start another WebApp server in a different port
    export SPRING_APPLICATION_JSON='{"server.port":8082}' \
        && WEBAPP_PORT=8082 \
        && start_webapp
    unset SPRING_APPLICATION_JSON
fi

for env_key in $(compgen -e); do
    if [[ ! ${env_key} =~ ^INSTRUMENTED_SERVICE(_[[:digit:]]+)?$ ]]; then
        continue
    fi
    jar=${!env_key}
    arg_key="${env_key}_ARGS"
    opt_key="${env_key}_OPTS"
    args=${!arg_key}
    opts=${!opt_key}

    cmd="java ${JAVA_OPTS} \
        ${opts} \
        -javaagent:${AGENT_HOME}/skywalking-agent.jar \
        -jar ${SERVICE_HOME}/${jar} \
        ${args}"
    echo "command: ${cmd}"
    touch ${SERVICE_LOG}/${env_key}.log
    eval ${cmd} >> ${SERVICE_LOG}/${env_key}.log 2>&1 &
done

tail -f ${OAP_LOG_DIR}/* \
        ${WEBAPP_LOG_DIR}/* \
        ${SERVICE_LOG}/* \
        ${ES_HOME}/logs/elasticsearch.log \
        ${ES_HOME}/logs/stdout.log
