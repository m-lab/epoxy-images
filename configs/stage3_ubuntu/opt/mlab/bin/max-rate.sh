#!/bin/bash

SITE=${HOSTNAME:6:5}
PROJECT=$(echo $HOSTNAME | cut -d. -f2)
SITEINFO_URL=siteinfo.${PROJECT}.measurementlab.net

while ! busybox nslookup ${SITEINFO_URL}; do
  echo "Name resolution failed."
done

MAX_RATE=$(curl --silent --show-error --location \
    https://${SITEINFO_URL}/v2/sites/max-rates.json \
    | jq -r ".${SITE}")

if [[ -z $MAX_RATE ]]; then
  echo "ERROR: Unable to determine NDT max-rate for site ${SITE}"
  exit 1
fi

echo -n $MAX_RATE > /etc/ndt-max-rate
