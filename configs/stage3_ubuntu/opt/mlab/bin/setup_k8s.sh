#!/bin/bash

curr_date=$(date +%FT%TZ)
exec 2> /var/log/setup_k8s.log-$curr_date 1>&2
ln --force --symbolic /var/log/setup_k8s.log-$curr_date /var/log/setup_k8s.log

set -euxo pipefail

# This script is intended to be called by epoxy_client as the action for the
# last stage in the boot process.  The actual epoxy config that calls this file
# can be found at:
#    https://github.com/m-lab/epoxy-images/blob/main/actions/stage3_ubuntu/stage3post.json
# This should be the final step in the boot process. Prior to this script
# running, we should have made sure that the disk is partitioned appropriately
# and mounted in the right places (one place to serve as a cache for Docker
# images, the other two to serve as repositories for core system data and
# experiment data, respectively)

# Save the arguments
GCP_PROJECT=${1:?GCP Project is missing.}
# IPV4="$2"  # Currently unused.
HOSTNAME=${3:?Node hostname is missing.}
K8S_TOKEN_URL=${4:?k8s token URL is missing. Node cannot join k8s cluster.}
K8S_TOKEN_ERROR_FILE="/tmp/k8s_token_error"

# Turn the hostname into its component parts.
MACHINE=${HOSTNAME:0:5}
SITE=${HOSTNAME:6:5}
METRO="${SITE/[0-9]*/}"

# This value will be used to populate the node label "mlab/managed", which will
# allow operators to differentiate betweeen "full", "minimal" and "BYOS"
# physical sites. Since k8s does not support commas in label values, any commas
# are converted to dashes.
MANAGED=$(cat /var/local/metadata/managed | tr ',' '-')

# Adds /opt/bin (k8s binaries) and /opt/mlab/bin (mlab binaries/scripts) to PATH.
# Also, be 100% sure /sbin and /usr/sbin are in PATH.
export PATH=$PATH:/sbin:/usr/sbin:/opt/bin:/opt/mlab/bin

# Capture K8S version for later usage.
RELEASE=$(kubelet --version | awk '{print $2}')

# Whether the site's transit is donated or not. Will be "true" or "false".
DONATED=$(
  curl --silent "https://siteinfo.${GCP_PROJECT}.measurementlab.net/v2/sites/donated.json" \
    | jq "any(. == \"${SITE}\")"
)

# Create a list of node labels
NODE_LABELS="mlab/machine=${MACHINE},"
NODE_LABELS+="mlab/site=${SITE},"
NODE_LABELS+="mlab/metro=${METRO},"
NODE_LABELS+="mlab/type=physical,"
NODE_LABELS+="mlab/project=${GCP_PROJECT},"
NODE_LABELS+="mlab/ndt-version=production,"
NODE_LABELS+="mlab/managed=${MANAGED},"
NODE_LABELS+="mlab/donated=${DONATED}"

sed -ie "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--node-labels=$NODE_LABELS |g" \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Make the directory /etc/kubernetes/manifests. The declaration staticPodPath in
# `staticPodPath` /var/lib/kubelet/config.yaml defines this and is a standard
# for k8s. If it doesn't exist the kubelet logs a message every few seconds that
# it doesn't exist, polluting the logs terribly.
mkdir --parents /etc/kubernetes/manifests

systemctl daemon-reload

# Fetch k8s cluster join data from K8S_TOKEN_URL. Curl should report most errors
# to stderr, so write stderr to a file so we can read any error code.
JOIN_DATA=$( curl --fail --silent --show-error -XPOST --data-binary "{}" \
    ${K8S_TOKEN_URL} 2> $K8S_TOKEN_ERROR_FILE )
# IF there was an error and the error was 408 (Request Timeout), then reboot
# the machine to reset the token timeout.
ERROR_408=$(grep '408 Request Timeout' $K8S_TOKEN_ERROR_FILE || :)
if [[ -n $ERROR_408 ]]; then
  /sbin/reboot
fi

# $JOIN_DATA should contain a simple JSON block with all the information needed
# to join the cluster.
api_address=$(echo "$JOIN_DATA" | jq -r '.api_address')
ca_hash=$(echo "$JOIN_DATA" | jq -r '.ca_hash')
token=$(echo "$JOIN_DATA" | jq -r '.token')

kubeadm join "$api_address"  --v 4  --token "$token" \
  --discovery-token-ca-cert-hash "$ca_hash"

systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

echo 'Success: everything we did appeared to work - good luck'
