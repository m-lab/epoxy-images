#!/bin/bash
#
# This script leverages the ePoxy boot server's "delete" extension, allowing a
# machine to leave the k8s cluster on shutdown.

set -euxo pipefail

export PATH=$PATH:/opt/bin

METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

# Collect data necessary to proceed.
api_load_balancer=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/api_load_balancer")
epoxy_extension_server=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/epoxy_extension_server")
hostname=$(hostname)
k8s_node=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/k8s_node")

# MIG instances will have an "instance-template" attribute, other VMs will not.
# Record the HTTP status code of the request into a variable. 200 means
# "instance-template" exists and that this is a MIG instance. 404 means it is
# not part of a MIG. We use this below to determine whether to attempt to
# append the unique 4 char suffix of MIG instances to the k8s node name.
is_mig=$(
  curl "${CURL_FLAGS[@]}" --output /dev/null --write-out "%{http_code}" \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/instance-template
)

# If this is a MIG instance, determine the random 4 char suffix of the instance
# name, and then append that to the base k8s node name. The result should be a
# typical M-Lab node/DNS name with a "-<xxxx>" string on the end. With this,
# the node name is still unique, but we can easily just strip off the last 5
# characters to get the name of the load balancer. Among other things, the
# uuid-annotator can use this value as its -hostname flag so that it knows how
# to annotate the data on this MIG instance.
node_name="$k8s_node"
if [[ $is_mig == "200" ]]; then
  node_suffix="${hostname##*-}"
  node_name="${k8s_node}-${node_suffix}"
fi

# Don't try to join the leave the cluster until at least one control plane node
# is ready.  Keep trying this forever, until it succeeds, as there is no point
# in going forward without it, as the epoxy-extension-server runs on API nodes.
api_status=""
until [[ $api_status == "200" ]]; do
  sleep 5
  api_status=$(
    curl --insecure --output /dev/null --silent --write-out "%{http_code}" \
      "https://${api_load_balancer}:6443/readyz" \
      || true
  )
done

# Generate a JSON snippet suitable for the ePoxy extension server, and then
# request a token.
# https://github.com/m-lab/epoxy/blob/main/extension/request.go#L36
extension_v1="{\"v1\":{\"hostname\":\"${node_name}\",\"last_boot\":\"$(date --utc +%Y-%m-%dT%T.%NZ)\"}}"

# Don't bother with any error checking on this request. This is a one-shot deal
# that will either work, or not, just before shutdown. Hopefully it will work
# almost all the time.
curl --data "$extension_v1" "http://${epoxy_extension_server}:8800/v1/delete_node"
