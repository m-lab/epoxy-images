#!/bin/bash

# This script writes out a Prometheus metric file which will be collected by the
# node_exporter textfile collector. Make sure that the textfile collector
# directory exists. And write out the stub metric file.
METRIC_DIR=/var/spool/node_exporter
METRIC_FILE=$METRIC_DIR/configure_tc_fq.prom
METRIC_FILE_TEMP=$(mktemp)
mkdir -p $METRIC_DIR
echo -n "node_configure_qdisc_success " > $METRIC_FILE_TEMP

SITE=${HOSTNAME:6:5}
SPEED=$(curl --silent --show-error --location \
    https://siteinfo.mlab-oti.measurementlab.net/v1/sites/switches.json \
    | jq -r ".${SITE}.uplink_speed")

if [[ "${SPEED}" == "10g" ]]; then
  MAXRATE="10gbit"
elif [[ "${SPEED}" == "1g" ]]; then
  MAXRATE="1gbit"
else
  echo "Unknown uplink speed '${SPEED}'. Not configuring default qdisc for eth0."
  echo -n "0" >> $METRIC_FILE_TEMP
  exit 1
fi

/sbin/tc qdisc replace dev eth0 root fq maxrate "${MAXRATE}"

if [[ $? -ne 0 ]]; then
  echo "Failed to configure qdisc fq on dev eth0 with max rate of: ${MAXRATE}"
  echo -n "0" >> $METRIC_FILE_TEMP
  exit 1
fi

# Even though tc's exit code was 0, be 100% sure that the configured value for
# maxrate is what we expect.
configured_maxrate=$(tc -json qdisc show dev eth0 | jq -r '.[0].options.maxrate')
if [[ $configured_maxrate != $MAXRATE ]]; then
  echo "maxrate of qdisc fq on eth0 is ${configured_maxrate}, but should be ${MAXRATE}"
  echo -n "0" >> $METRIC_FILE_TEMP
  exit 1
fi

echo -n "1" >> $METRIC_FILE_TEMP
mv $METRIC_FILE_TEMP $METRIC_FILE
echo "Set maxrate for qdisc fq on dev eth0 to: ${MAXRATE}"
