#!/usr/bin/env bash

#/*******************************************************************************
# Copyright (c) 2016 DigitalOcean, Inc.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#/*******************************************************************************

source $(echo $0 | sed -e "s/\(.*\/\)*.*/\1.\//g")/cb_common.sh

LOAD_PROFILE=$1
LOAD_LEVEL=$2
LOAD_DURATION=$3
LOAD_ID=$4
SLA_RUNTIME_TARGETS=$5

if [[ -z "$LOAD_PROFILE" || -z "$LOAD_LEVEL" || -z "$LOAD_DURATION" || -z "$LOAD_ID" ]]
then
    syslog_netcat "Usage: cb_btest.sh <load_profile> <load level> <load duration> <load_id> [sla_targets]"
    exit 1
fi

BTEST_EXECUTABLE=$(which btest)
if [[ $? -ne 0 ]]
then
    BTEST_EXECUTABLE=${dir}/cbtool/3rd_party/btest/btest
fi

BTEST_DATA_DIR=$(get_my_ai_attribute_with_default btest_data_dir ~/btestfile)        

update_app_errors 0 reset

# TODO:
# 1. Support -X trim flag on SSD-backed volumes
# 2. Issue sudo fstrim /

if [[ $LOAD_PROFILE == "default" ]]
then
    LOAD_PROFILE="4096;32;50;100;500"
fi
    
threads=$LOAD_LEVEL
block=$(echo $LOAD_PROFILE | cut -d ";" -f 1)
queuedepth=$(echo $LOAD_PROFILE | cut -d ";" -f 2)
read_percent=$(echo $LOAD_PROFILE | cut -d ";" -f 3)
random_percent=$(echo $LOAD_PROFILE | cut -d ";" -f 4)
sizemb=$(echo $LOAD_PROFILE | cut -d ";" -f 5)

sudo rm -f $BTEST_DATA_DIR/btestfile;

# This has no effect if # ./install -r workload -w btest # is done properly
# No effect if libaio is installed properly via ./install
if [ x"$(ldconfig -p | grep libaio)" == x ] ; then
    export LD_PRELOAD=${dir}/libaio.so.1.0.1
fi

CMDLINE="sudo $BTEST_EXECUTABLE -F -T $threads -b $block -D -l ${sizemb}m -w $queuedepth -t $LOAD_DURATION -F $random_percent $read_percent $BTEST_DATA_DIR/btestfile"

syslog_netcat "Benchmarking btest SUT: BTEST=${my_ip_addr} with LOAD_LEVEL=${LOAD_LEVEL} and LOAD_DURATION=${LOAD_DURATION} (LOAD_ID=${LOAD_ID} and BLOCK SIZE $block AIO QUEUE DEPTH $queuedepth % READ $read_percent % RANDOM $random_percent SIZE $sizemb MB)"

OUTPUT_FILE=$(mktemp)

execute_load_generator "${CMDLINE}" ${OUTPUT_FILE} ${LOAD_DURATION}
sudo rm -f $BTEST_DATA_DIR/btestfile;

tp=`grep "Total:" ${OUTPUT_FILE} | grep -v ms | cut -d " " -f 4`
lat=`grep "Total:" ${OUTPUT_FILE} | grep -v ms | cut -d " " -f 8`

syslog_netcat "btest run complete. Will collect and report the results $tp $lat"

~/cb_report_app_metrics.py load_id:${LOAD_ID}:seqnum \
load_profile:${LOAD_PROFILE}:name \
load_level:${LOAD_LEVEL}:load \
load_duration:${LOAD_DURATION}:sec \
errors:$(update_app_errors):num \
completion_time:$(update_app_completiontime):sec \
quiescent_time:$(update_app_quiescent):sec \
throughput:${tp}:tps \
latency:${lat}:msec \
${SLA_RUNTIME_TARGETS}

rm ${OUTPUT_FILE}

exit 0
