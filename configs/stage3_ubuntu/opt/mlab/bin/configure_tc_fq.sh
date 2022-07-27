#!/bin/bash

# This script writes out a Prometheus metric file which will be collected by the
# node_exporter textfile collector.
METRIC_FILE=/cache/data/node-exporter/configure_tc_fq.prom
METRIC_FILE_TEMP=$(mktemp)
echo -n "node_configure_qdisc_success " > $METRIC_FILE_TEMP

# Append the passed status code to the temporary metric file, overwrite the
# metric file with the temp metric file, and make the metric file world readable.
function overwrite_metric_file {
  local status=$1
  echo "$status" >> $METRIC_FILE_TEMP
  mv $METRIC_FILE_TEMP $METRIC_FILE
  chmod 644 $METRIC_FILE
}

SITE=${HOSTNAME:6:5}
SPEED=$(curl --silent --show-error --location \
    https://siteinfo.mlab-oti.measurementlab.net/v1/sites/switches.json \
    | jq -r ".${SITE}.uplink_speed")

# Internally, tc stores rates as 32-bit unsigned integers in bps (bytes per
# second).  Because of this, and to make comparisons easier later in the script,
# we convert the "g" value to a bps value.
if [[ "${SPEED}" == "10g" ]]; then
  MAXRATE="1250000000"
elif [[ "${SPEED}" == "1g" ]]; then
  MAXRATE="125000000"
else
  echo "Unknown uplink speed '${SPEED}'. Not configuring default qdisc for eth0."
  overwrite_metric_file 0
  exit 1
fi

/sbin/tc qdisc replace dev eth0 root fq maxrate "${MAXRATE}bps"

if [[ $? -ne 0 ]]; then
  echo "Failed to configure qdisc fq on dev eth0 with max rate of: ${MAXRATE}"
  overwrite_metric_file 0
  exit 1
fi

# Even though tc's exit code was 0, be 100% sure that the configured value for
# maxrate is what we expect.
configured_maxrate=$(tc -json qdisc show dev eth0 | jq -r '.[0].options.maxrate')
if [[ $configured_maxrate != $MAXRATE ]]; then
  echo "maxrate of qdisc fq on eth0 is ${configured_maxrate}, but should be ${MAXRATE}"
  overwrite_metric_file 0
  exit 1
fi

overwrite_metric_file 1
echo "Set maxrate for qdisc fq on dev eth0 to: ${MAXRATE}"
