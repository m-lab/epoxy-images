#!/bin/bash

set -euxo pipefail

METADATA_DIR=/var/local/metadata
mkdir -p $METADATA_DIR

ZONE=$(
  curl --silent -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/zone"
)
echo ${ZONE##*/} > $METADATA_DIR/zone

EXTERNAL_IP=$(
  curl --silent -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip"
)
echo $EXTERNAL_IP > $METADATA_DIR/external-ip

EXTERNAL_IPV6=$(
  curl --silent -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ipv6s"
)
echo $EXTERNAL_IPV6 > $METADATA_DIR/external-ipv6

MACHINE_TYPE=$(
  curl --silent -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/machine-type"
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
