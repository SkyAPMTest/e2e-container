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

FROM openjdk:8-jre-alpine

LABEL maintainer="kezhenxu94@apache.org"

ENV SW_HOME=/skywalking
ENV ZK_HOME=/zk
ENV ES_HOME=/es

# MODE: standalone/cluster
# standalone: will start only one OAP server
# cluster: will start a cluster coordinator (ZK) and multiple OAP servers
ENV MODE=standalone

EXPOSE 8081 8082
EXPOSE 11800 12800 11801 12801
EXPOSE 2181 9200
EXPOSE 9090 9091 9092 9093 9094

RUN apk update && apk add bash

VOLUME $SW_HOME
VOLUME $ZK_HOME
VOLUME $ES_HOME

WORKDIR $ZK_HOME
RUN wget http://mirror.bit.edu.cn/apache/zookeeper/zookeeper-3.5.5/apache-zookeeper-3.5.5-bin.tar.gz
#COPY apache-zookeeper-3.5.5-bin.tar.gz .

WORKDIR $ES_HOME
RUN wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.3.2.tar.gz
#COPY elasticsearch-oss-6.3.2.tar.gz .

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY clusterize.awk /clusterize.awk

ENTRYPOINT ["bash", "/docker-entrypoint.sh"]
