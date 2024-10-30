#!/bin/bash

set -ux

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

# For network cards with multiple interfaces, the kernel may not assign eth*
# device names in the same order between boots. Determine which eth* interface
# has a layer 2 link, and use it as our interface. There should only be one
# with a link. Set the default to eth0 as a fallback.
DEVICE="eth0"
for i in /sys/class/net/eth*; do
  CARRIER=$(cat $i/carrier)
  if [[ $CARRIER == "1" ]]; then
    DEVICE=$(basename $i)
    break
  fi
done

# Determine the uplink speed of the site. See MAXRATE below for rationale.
SPEED=$(
  curl --silent --show-error --location \
    https://siteinfo.mlab-oti.measurementlab.net/v2/sites/registration.json \
    | jq -r ".[\"${HOSTNAME}\"] | .Uplink"
)

# If machines are connected to the switch at a rate which is faster than the
# uplink speed, the machines can overflow buffers in the switch, causing
# excessive discards. Today, this is only true at the few remaining sites with
# 1g uplinks. If the uplink is 1g set the maxrate parameter to the speed of the
# uplink to help avoid overwhelming the switch.
MAXRATE=""
if [[ $SPEED == "1g" ]]; then
  MAXRATE="maxrate 1gbit"
fi

/sbin/tc qdisc replace dev $DEVICE root fq $MAXRATE

if [[ $? -ne 0 ]]; then
  echo "Failed to configure qdisc fq on dev ${DEVICE}"
  write_metric_file 0
  exit 1
fi

write_metric_file 1
echo "Successfully configured qdisc fq on dev ${DEVICE}"

