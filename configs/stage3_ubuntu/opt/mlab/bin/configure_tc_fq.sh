#!/bin/bash

# This script writes out a Prometheus metric file which will be collected by the
# node_exporter textfile collector. Make sure that METRIC_DIR exists.
METRIC_DIR=/cache/data/node-exporter
METRIC_FILE=$METRIC_DIR/configure_tc_fq.prom
METRIC_FILE_TEMP=$(mktemp)
mkdir -p $METRIC_DIR
echo -n "node_configure_qdisc_success " > $METRIC_FILE_TEMP

# Append the passed status code to the temporary metric file, then move the temp
# metric file to the proper location, making it world readable.
function write_metric_file {
  local status=$1
  echo "$status" >> $METRIC_FILE_TEMP
  mv $METRIC_FILE_TEMP $METRIC_FILE
  chmod 644 $METRIC_FILE
}

SPEED=$(
  curl --silent --show-error --location \
    https://siteinfo.mlab-oti.measurementlab.net/v2/sites/registration.json \
    | jq -r ".[\"${HOSTNAME}\"] | .Uplink"
  )

/sbin/tc qdisc replace dev eth0 root fq

if [[ $? -ne 0 ]]; then
  echo "Failed to configure qdisc fq on dev eth0"
  write_metric_file 0
  exit 1
fi

write_metric_file 1
echo "Set maxrate for qdisc fq on dev eth0 to: ${MAXRATE}"

