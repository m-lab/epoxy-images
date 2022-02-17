#!/bin/bash

SITE=${HOSTNAME:6:5}
PROJECT=$(echo $HOSTNAME | cut -d. -f2)
SITEINFO_URL=siteinfo.${PROJECT}.measurementlab.net

# Even though the systemd service (max-rate.service) which calls this script is
# configured to run _After_ the nss-lookup.target, for some reason DNS
# resolution, at least for external hosts, is still not functional at this
# point. Run a loop waiting for name resolution to start working before moving on.
while busybox nslookup ${SITEINFO_URL} | grep SERVFAIL &> /dev/null; do
  :
done

MAX_RATE=$(curl --silent --show-error --location \
    https://${SITEINFO_URL}/v2/sites/max-rates.json \
    | jq -r ".${SITE}")

if [[ -z $MAX_RATE ]]; then
  echo "ERROR: Unable to determine NDT max-rate for site ${SITE}"
  exit 1
fi

echo -n $MAX_RATE > /etc/ndt-max-rate
