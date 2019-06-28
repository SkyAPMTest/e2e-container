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

#!/usr/bin/env sh

JAVA_OPTS="-Xms256M -Xmx512M"

cd ${SW_HOME}/

export OAP_HOME=${OAP_HOME:-.}
export OAP_HOST=${OAP_HOST:-localhost}
export OAP_PORT=${OAP_PORT:-11800}

export WEBAPP_HOME=${WEBAPP_HOME:-.}
export WEBAPP_HOST=${WEBAPP_HOST:-localhost}
export WEBAPP_PORT=${WEBAPP_PORT:-8080}

export AGENT_HOME=${AGENT_HOME:-agent}

export CLIENT_HOME=${CLIENT_HOME:-/home}
export CLIENT_JAR=${CLIENT_JAR:-client.jar}

sh bin/oapService.sh > /dev/null 2>&1 &
sh bin/webappService.sh > /dev/null 2>&1 &

for i in `seq 1 12`; do
    nc -z ${OAP_HOST} ${OAP_PORT}
    if [[ "$?" -ne 0 ]]; then
        echo "checking the readiness of oap server"
        sleep 10
    fi
done

nc -zv ${OAP_HOST} ${OAP_PORT}

if [[ "$?" -ne 0 ]]; then
    echo "oap server failed to start in 120 seconds: "
    cat ${OAP_HOME}/logs/*
    exit 1
fi

echo "oap server is ready for connections"

for i in `seq 1 12`; do
    nc -z ${WEBAPP_HOST} ${WEBAPP_PORT}
    if [[ "$?" -ne 0 ]]; then
        echo "checking the readiness of web app"
        sleep 10
    fi
done

nc -zv ${WEBAPP_HOST} ${WEBAPP_PORT}

if [[ "$?" -ne 0 ]]; then
    echo "web app failed to start in 120 seconds"
    cat ${WEBAPP_HOME}/logs/*
    exit 1
fi

echo "web app is ready for connections"

mkdir -p ${CLIENT_HOME}/logs/

for jar in $(printenv | grep -e '^CLIENT_JAR'); do
    java ${JAVA_OPTS} \
        -javaagent:${AGENT_HOME}/skywalking-agent.jar \
        -DSW_AGENT_COLLECTOR_BACKEND_SERVICES=${OAP_HOST}:${OAP_PORT} \
        -jar ${CLIENT_HOME}/${jar/CLIENT_JAR*=/} > ${CLIENT_HOME}/logs/${jar/CLIENT_JAR*=/}.log 2>&1 &
done

tail -f ${OAP_HOME}/logs/* ${WEBAPP_HOME}/logs/* ${CLIENT_HOME}/logs/*
