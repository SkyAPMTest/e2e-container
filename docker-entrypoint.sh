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

JAVA_OPTS="${JAVA_OPTS:-"-Xms256M -Xmx512M"}"

export MODE=${MODE:-standalone}

export SW_HOME=${SW_HOME:-/sw}
export ZK_HOME=${ZK_HOME:-/zk}
export ES_HOME=${ES_HOME:-/es}

export OAP_HOME=${OAP_HOME:-${SW_HOME}}
export LOG_HOME=${LOG_HOME:-/tmp/logs}

export SW_CORE_GRPC_HOST=${SW_CORE_GRPC_HOST:-0.0.0.0}
export SW_CORE_GRPC_PORT=${SW_CORE_GRPC_PORT:-11800}
export SW_CORE_REST_HOST=${SW_CORE_REST_HOST:-0.0.0.0}
export SW_CORE_REST_PORT=${SW_CORE_REST_PORT:-12800}

export OAP_LOG_DIR=${OAP_LOG_DIR:-${LOG_HOME}/oap}

export WEBAPP_HOME=${WEBAPP_HOME:-${SW_HOME}}
export WEBAPP_HOST=${WEBAPP_HOST:-localhost}
export WEBAPP_PORT=${WEBAPP_PORT:-8081}
export WEBAPP_LOG_DIR=${WEBAPP_LOG_DIR:-${LOG_HOME}/webapp}

export AGENT_HOME=${AGENT_HOME:-${SW_HOME}/agent}

export SERVICE_HOME=${SERVICE_HOME:-/home}
export SERVICE_LOG=${SERVICE_LOG:-${LOG_HOME}/service}

mkdir -p ${OAP_LOG_DIR}
mkdir -p ${WEBAPP_LOG_DIR}
mkdir -p ${SERVICE_LOG}

#######################################
# Check whether a tcp host:port is available/open or not
#
# Globals:
#   None
# Arguments:
#   host: tcp host whose availability is to be checked
#   port: tcp port whose availability is to be checked
#   count: how many times to check before giving up
#   interval: how many seconds between two checking
#   checking_message: message to display when checking, optional
# Returns:
#   0 if the given host:port available, otherwise unavailable
#######################################
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

#######################################
# Start a zookeeper server and wait until it's ready for connection
#
# Globals:
#   ZK_HOME: the root directory of zookeeper,
#            under which should exist directories such as `bin`, `conf`, etc.
# Arguments:
#   None
# Returns:
#   None
#######################################
start_zk() {
    original_pwd=$(pwd)

    cd ${ZK_HOME}

    bash ${ZK_HOME}/bin/zkServer.sh start 2>&1

    check_tcp localhost 2181 12 10 "waiting for the zookeeper to be ready"

    if [[ $? -ne 0 ]]; then
        echo "zookeeper server failed to start in 120 seconds: "
        cat ${ZK_HOME}/logs/*
        exit 1
    fi

    cd ${original_pwd}
}

#######################################
# Start a elasticsearch server and wait until it's ready for connection
#
# Globals:
#   ES_HOME: the root directory of elasticsearch,
#            under which should exist directories such as `bin`, `conf`, etc.
#   ES_JAVA_OPTS: the JAVA_OPTS used only for starting the es instance
# Arguments:
#   None
# Returns:
#   None
#######################################
start_es() {
    original_pwd=$(pwd)

    cd ${ES_HOME}

    export ES_TMPDIR=`mktemp -d -t elasticsearch.XXXXXXXX`
    export ES_JAVA_OPTS=${ES_JAVA_OPTS:-"-Xms1g -Xmx1g"}

    addgroup -S es \
        && adduser -S es -G es -s /bin/bash -D \
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

#######################################
# Start an OAP server node and wait until it's ready for connection
#
# Globals:
#   SW_HOME: the root directory of SkyWalking,
#            under which should exist directories such as `bin`, `config`, `agent`, `webapp` etc.
#   SW_CORE_GRPC_HOST:
#   SW_CORE_GRPC_PORT:
#   OAP_LOG_DIR: into which the logging files will be put
# Arguments:
#   mode: `init` will make the OAP server node start in `init` mode (initializing indices/tables),
#         any value other than `init` will make the OAP server start normally
# Returns:
#   None
#######################################
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
              "waiting for the oap server to be ready: ${SW_CORE_GRPC_HOST}:${SW_CORE_GRPC_PORT}"

    if [[ $? -ne 0 ]]; then
        echo "oap server failed to start in ${check_times} * ${check_interval} seconds: "
        cat ${OAP_LOG_DIR}/*
        exit 1
    fi

    echo "oap server is ready for connections"

    cd ${original_pwd}
}

#######################################
# Start a Web App server node and wait until it's ready for connection
#
# Globals:
#   SW_HOME: the root directory of SkyWalking,
#            under which should exist directories such as `bin`, `config`, `agent`, `webapp` etc.
#   WEBAPP_LOG_DIR: into which the logging files will be put
# Arguments:
#   address: the `address` where this web app should be bound to
#            (a.k.a server.address in spring application.yml)
#   port: the `port` where this web app should be bound to
#            (a.k.a server.port in spring application.yml)
# Returns:
#   None
#######################################
start_webapp() {
    address=$1
    port=$2

    original_pwd=$(pwd)

    cd ${SW_HOME}/

    SPRING_APPLICATION_JSON="{\"server.address\":\"${address}\",\"server.port\":${port}}" \
        bash bin/webappService.sh > /dev/null 2>&1 &

    check_tcp ${address} \
          ${port} \
          ${check_times} \
          ${check_interval} \
          "waiting for the web app to be ready: ${address}:${port}"

    if [[ $? -ne 0 ]]; then
        echo "web app failed to start in ${check_times} * ${check_interval} seconds"
        cat ${WEBAPP_LOG_DIR}/*
        exit 1
    fi

    echo "web app is ready for connections"

    cd ${original_pwd}
}

#######################################
# Start the instrumented services
#
# Globals:
#   AGENT_HOME: the SkyWalking agent directory, under which should exist: skywalking-agent.jar, config, etc.
#   SERVICE_HOME: the root directory where the instrumented service jar files locate
#   SERVICE_LOG: directory to put the log files, default: /tmp/logs/service/
#   INSTRUMENTED_SERVICE(_N): the instrumented service jar file, where `_N` is optional if
#       there is only one service to run; use `_N` as suffix if there're multiple services (`N` is number)
#   INSTRUMENTED_SERVICE(_N)_OPTS: the JAVA_OPTS to be used
#       when running the corresponding `INSTRUMENTED_SERVICE(_N)` service
#   INSTRUMENTED_SERVICE(_N)_ARGS: the arguments to be used
#       when running the corresponding `INSTRUMENTED_SERVICE(_N)` service
# Arguments:
#   None
# Returns:
#   None
#######################################
start_instrumented_services() {

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
        echo ${cmd}
        touch ${SERVICE_LOG}/${env_key}.log
        eval ${cmd} >> ${SERVICE_LOG}/${env_key}.log 2>&1 &
    done

}

export -f check_tcp
export -f start_zk
export -f start_es
export -f start_oap
export -f start_webapp
export -f start_instrumented_services

echo "starting e2e container in mode: ${MODE}"

if [[ ! -d /rc.d ]]; then
    echo "/rc.d doesn't exist, nothing to do"
    exit 0
fi

for script in $(ls /rc.d | sort); do
    echo "executing script: $script..."
    bash /rc.d/${script}
done
