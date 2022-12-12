#!/bin/bash
#
# M-Lab has a notion of a "metadata" directory on machines. This directory (by
# convention "/var/local/metadata") can contain any number of files that contain
# data about the operating environment of the machine (e.g., kernel version).
# Experiments can mount this directory and make use of the metadata to annotate
# its own data, allowing users of M-Lab data to potentially query based on this
# metadata. This script writes out a number of metadata files to
# /var/local/metadata. Most of it is gathered from the GCE metadata server.

set -euxo pipefail

METADATA_DIR=/var/local/metadata
mkdir -p $METADATA_DIR

BASE_URL="http://metadata.google.internal/computeMetadata/v1/instance"

ZONE=$(
  curl --silent -H "Metadata-Flavor: Google" "${BASE_URL}/zone"
)
echo ${ZONE##*/} > $METADATA_DIR/zone

EXTERNAL_IP=$(
  curl --silent -H "Metadata-Flavor: Google" "${BASE_URL}/network-interfaces/0/access-configs/0/external-ip"
)
echo $EXTERNAL_IP > $METADATA_DIR/external-ip

EXTERNAL_IPV6=$(
  curl --silent -H "Metadata-Flavor: Google" "${BASE_URL}/network-interfaces/0/ipv6s"
)
echo $EXTERNAL_IPV6 > $METADATA_DIR/external-ipv6

MACHINE_TYPE=$(
  curl --silent -H "Metadata-Flavor: Google" "${BASE_URL}/machine-type"
)
echo ${MACHINE_TYPE##*/} > $METADATA_DIR/machine-type

# The network tier is apparently not available from the metadata server, yet it
# is available through the API using gcloud at this attribute:
#
# networkInterfaces[0].accessConfigs[0].networkTier
#
# So, for now, just statically set the network tier to PREMIUM. This is the
# default, and anything less isn't even available in all regions. We are
# unlikely to change this.
echo "PREMIUM" > $METADATA_DIR/network-tier

echo $(uname -r) > $METADATA_DIR/kernel-version
