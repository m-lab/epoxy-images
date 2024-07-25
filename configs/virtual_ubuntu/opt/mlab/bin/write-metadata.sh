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

# MIG instances will have a "created-by" attribute, standalone VMs will not.
# Record the HTTP status code of the request into a variable. 200 means
# "created-by" exists and therefore this is a MIG instance. Any other response
# code means it was not created by an instance group manager and is not a MIG
# instance.  This value is used to determine whether to flag this instance as
# loadbalanced or not. Additionally, it is used to determine which external IP
# addresses should be recorded, those of the VM or the ones associated with a
# load balancer.
#
# https://cloud.google.com/compute/docs/instance-groups/getting-info-about-migs#checking_if_a_vm_instance_is_part_of_a_mig
is_mig=$(
  curl "${CURL_FLAGS[@]}" --output /dev/null --write-out "%{http_code}" \
    "${METADATA_URL}/attributes/created-by"
)

if [[ $is_mig == "200" ]]; then
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
