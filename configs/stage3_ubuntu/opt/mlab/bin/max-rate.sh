#!/bin/bash
#
# max-rate.sh downloads the siteinfo format max-rates.json, determines the
# NDT max-rate for the current site, and then writes that value to a file in the
# local filesystem. ndt-server will read this value in order to properly set its
# -txcontroller.max-rate flag. This script takes no arguments, and the only
# input it uses is the $HOSTNAME environment variable to determine the node's
# site name and GCP project.

SITE=${HOSTNAME:6:5}
PROJECT=$(echo $HOSTNAME | cut -d. -f2)
SITEINFO_URL=siteinfo.${PROJECT}.measurementlab.net
METADATA_DIR=/var/local/metadata

# Even though the systemd service (max-rate.service) which calls this script is
# configured to run _After_ the nss-lookup.target, for some reason DNS
# resolution, at least for external hosts, is still not functional at this
# point. Run a loop waiting for name resolution to start working before moving on.
while busybox nslookup ${SITEINFO_URL} | grep SERVFAIL &> /dev/null; do
  sleep .1
done

MAX_RATE=$(curl --silent --show-error --location \
    https://${SITEINFO_URL}/v2/sites/max-rates.json \
    | jq -r ".${SITE}")

if [[ -z $MAX_RATE ]]; then
  echo "ERROR: Unable to determine NDT max-rate for site ${SITE}"
  exit 1
fi

mkdir -p ${METADATA_DIR}

echo -n $MAX_RATE > $METADATA_DIR/iface-max-rate
