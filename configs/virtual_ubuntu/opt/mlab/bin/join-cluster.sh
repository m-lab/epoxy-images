#!/bin/bash
#
# This script leverages the ePoxy boot server's "allocate_k8s_token" extension
# to fetch a cluster bootstrap token, and uses it to automatically join the
# M-Lab platform cluster.

set -euxo pipefail

export PATH=$PATH:/opt/bin

METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

# Collect data necessary to proceed.
project=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/project-id")
api_url="api-platform-cluster.${project}.measurementlab.net:6443"
external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/access-configs/0/external-ip")
fqdn=$(hostname --fqdn)
hostname=$(hostname)
stage1_url="https://epoxy-boot-api.${project}.measurementlab.net/v1/boot/${fqdn}/stage1.json"

# Keep trying to get a token until it succeeds, since there is no point in
# continuing without a token, and exiting the script isn't necessarily
# productive either. Failure could be due to some bug that won't be resolved
# soon, but it could also be that the control plane machines are in the process
# of being created or rebooted, or otherwise temporarily unavailable. For
# example, Terraform creates resources in parallel, and it's not impossible that
# a machine running this script could be up and running before the control plane
# is ready.
token=""
until [[ $token ]]; do
  token_url=$(
    curl --silent --location --request POST "$stage1_url" | \
      jq -r '.kargs."epoxy.allocate_k8s_token"'
  )
  token=$(curl --silent --location --request POST "$token_url" || true)
done

# TODO (kinkade): this is GCP specific and will not work outside of GCP. This
# will have to be made more generic before we can join VMs from other cloud
# providers. A current proposal is to have the token-server return not only a
# token, but also the CA cert hash, but this has yet to be implemented.
gsutil cp "gs://epoxy-${project}/latest/stage3_ubuntu/setup_k8s.sh" /tmp/setup_k8s.sh
ca_hash=$(egrep -o 'sha256:[[:alnum:]]+' /tmp/setup_k8s.sh)

# Set up necessary labels for the node.
node_labels="mlab/machine=${hostname:0:5},mlab/site=${hostname:6},mlab/metro=${hostname:6:3},mlab/type=virtual,mlab/run=ndt,mlab/project=${project}"
sed -ie "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--node-labels=$node_labels |g" \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

kubeadm join $api_server --token $token --discovery-token-ca-cert-hash $ca_hash --node-name $fqdn

# https://github.com/flannel-io/flannel/blob/master/Documentation/kubernetes.md#annotations
kubectl --kubeconfig /etc/kubernetes/kubelet.conf annotate node $fqdn \
  flannel.alpha.coreos.com/public-ip-overwrite=${external_ip} \
  --overwrite=true
