#!/bin/bash

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
  exit 1
fi

/sbin/tc qdisc replace dev eth0 root fq maxrate "${MAXRATE}"

if [[ $? -ne 0 ]]; then
  echo "Failed to configure qdisc fq on dev eth0 with max rate of: ${MAXRATE}"
  exit 1
fi

echo "Set maxrate for qdisc fq on dev eth0 to: ${MAXRATE}"
