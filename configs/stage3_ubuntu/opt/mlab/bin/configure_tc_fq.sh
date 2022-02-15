#!/bin/bash

MAX_RATE=$(cat /etc/ndt-max-rate)
if [[ -z $MAX_RATE ]]; then
  echo "ERROR: NDT max-rate not found in /etc/ndt-max-rate."
  echo "Not configuring default qdisc for eth0."
  exit 1
fi

/sbin/tc qdisc replace dev eth0 root fq maxrate "${MAXRATE}"

echo "Set maxrate for qdisc fq on dev eth0 to: ${MAXRATE}"
