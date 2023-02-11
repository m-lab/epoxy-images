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

zone=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/zone")
echo -n ${zone##*/} > $METADATA_DIR/zone

external_ip=$(
  curl "${CURL_FLAGS[@]}" "${METADATA_URL}/network-interfaces/0/access-configs/0/external-ip"
)
echo -n $external_ip > $METADATA_DIR/external-ip

external_ipv6=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/network-interfaces/0/ipv6s")
echo -n $external_ipv6 > $METADATA_DIR/external-ipv6

machine_type=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/machine-type")
echo -n ${machine_type##*/} > $METADATA_DIR/machine-type

# Write the MIG load balancer name to a file, which will be used by
# uuid-annotator to determine which node name to use from the annotations.json
# file. It cannot use hostname directly because hostnames and node names on
# virtual nodes do not match entries in siteinfo. The virtual machines are part
# of managed instance groups in a region, and they all have unique
# non-deterministic names. Both physical and virtual nodes will this metadata
# file to provide a common interface for uuid-annotator.
node_name=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/attributes/k8s_node")
echo -n $node_name > $METADATA_DIR/node-name

# The network tier is apparently not available from the metadata server, yet it
# is available through the API using gcloud at this attribute:
#
# networkInterfaces[0].accessConfigs[0].networkTier
#
# So, for now, just statically set the network tier to PREMIUM. This is the
# default, and anything less isn't even available in all regions. We are
# unlikely to change this.
echo -n "PREMIUM" > $METADATA_DIR/network-tier

echo -n $(uname -r) > $METADATA_DIR/kernel-version
