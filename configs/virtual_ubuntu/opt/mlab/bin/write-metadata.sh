#!/bin/bash
#
# M-Lab has a convention of a "metadata" directory on machines. This directory
# ("/var/local/metadata") can contain any number of files that contain data
# about the operating environment of the machine (e.g., kernel version).
# Experiments can mount this directory and make use of the metadata to annotate
# its own data, allowing users of M-Lab data to potentially query based on this
# metadata. This script writes out a number of metadata files to
# /var/local/metadata. Most of it is gathered from the GCE metadata server.

set -euxo pipefail

METADATA_DIR=/var/local/metadata
METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

mkdir -p $METADATA_DIR

loadbalanced=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/attributes/loadbalanced")
echo -n ${loadbalanced} > $METADATA_DIR/loadbalanced

if [[ $loadbalanced == "true" ]]; then
  # It sometimes takes a while for GCE to fully populating VM metadata,
  # specifically the "forwarded-ip[v6]s" values, requests for which were
  # occasionally returning a 404, other times not. This loop just makes sure
  # that one of those values exists before trying to read the value.
  metadata_status=""
  until [[ $metadata_status == "200" ]]; do
    sleep 5
    metadata_status=$(
      curl "${CURL_FLAGS[@]}" --output /dev/null --write-out "%{http_code}" \
        "${METADATA_URL}/network-interfaces/0/forwarded-ips/0" \
        || true
    )
  done
  echo -n "true" > $METADATA_DIR/loadbalanced
  external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/network-interfaces/0/forwarded-ips/0")
  external_ipv6=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/network-interfaces/0/forwarded-ipv6s/0")
else
  echo -n "false" > $METADATA_DIR/loadbalanced
  external_ip=$(
    curl "${CURL_FLAGS[@]}" "${METADATA_URL}/network-interfaces/0/access-configs/0/external-ip"
  )
  external_ipv6=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/network-interfaces/0/ipv6s")
fi

echo -n $external_ip > $METADATA_DIR/external-ip
echo -n $external_ipv6 > $METADATA_DIR/external-ipv6

zone=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/zone")
echo -n ${zone##*/} > $METADATA_DIR/zone

machine_type=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/machine-type")
echo -n ${machine_type##*/} > $METADATA_DIR/machine-type

# The network tier is apparently not available from the metadata server, yet it
# is available through the API using gcloud at this attribute:
#
# networkInterfaces[0].accessConfigs[0].networkTier
#
# For now, just statically set the network tier to PREMIUM. This is the default,
# and STANDARD isn't even available in all regions. However, we do want to do
# some testing with STANDARD tier networking, and ideally we could/should be
# able to set this to the correct value in every case.
echo -n "PREMIUM" > $METADATA_DIR/network-tier

echo -n $(uname -r) > $METADATA_DIR/kernel-version

# For virtual machines this indicates that M-Lab manages only the machine and
# none of the infrastructure upstream of it.
echo -n "machine" > $METADATA_DIR/managed

# Store the 3-letter IATA code. This may be used, for example, by M-Lab
# Autojoin VMs.
echo $HOSTNAME | sed -rn 's|.+([a-z]{3})[0-9t]{2}.+|\1|p' > $METADATA_DIR/iata-code

