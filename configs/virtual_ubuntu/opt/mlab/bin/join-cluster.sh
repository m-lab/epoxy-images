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
external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/access-configs/0/external-ip")
hostname=$(hostname)
k8s_labels=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/k8s_labels")
k8s_node=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/k8s_node")
lb_dns=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/lb_dns")
project=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/project-id")
token_server_dns=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/token_server_dns")

# Don't try to join the cluster until at least one control plane node is ready.
# Keep trying this forever, until it succeeds, as there is no point in going
# forward until the API is up.  In most cases, the control plane should be
# present already, except in the case where the control plane cluster is being
# initialized, in which case this node may be up and running and wanting to join
# before the control plane is ready.
api_status=""
until [[ $api_status == "200" ]]; do
  sleep 5
  api_status=$(
    curl --insecure --output /dev/null --silent --write-out "%{http_code}" \
      "https://${lb_dns}:6443/readyz" \
      || true
  )
done

# Wait a while after the control plane is accessible on the API port, since in
# the case where the cluster is being initialized, there are a few housekeeping
# items to handle, such as uploading the latest CA cert hash to the project metadata.
sleep 60


# Generate a JSON snippet suitable for the token-server, and then request a
# token.  https://github.com/m-lab/epoxy/blob/main/extension/request.go#L36
extension_v1="{\"v1\":{\"hostname\":\"${hostname}\",\"last_boot\":\"$(date --utc +%Y-%m-%dT%T.%NZ)\"}}"

# Fetch a token from the token-server.
#
# TODO (kinkade): this only works from within GCP, so is not a long term
# solution. It is just a stop-gap to get GCP VMs able to join the cluster until
# we have implemented a more global solution that will support any cloud
# provider. Going through ePoxy will not work for VMs in a managed instance
# group (MIG), since siteinfo, ePoxy and Locate will only know about the load
# balancer IP address, not the possibly ephemeral public IP of an auto-scaled
# instance in a MIG.
token=$(curl --data "$extension_v1" "http://${token_server_dns}:8800/v1/allocate_k8s_token" || true)

if [[ -z $token ]]; then
  echo "Failed to get a cluster bootstrap join token from the token-server"
  exit 1
fi

# TODO (kinkade): this is GCP specific and will not work outside of GCP. This
# will have to be made more generic before we can join VMs from other cloud
# providers. A current proposal is to have the token-server return not only a
# token, but also the CA cert hash, but this has yet to be implemented.
#
# Fetch the ca_cert_hash stored in project metadata.
ca_cert_hash=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/platform_cluster_ca_hash")

# Set up necessary labels for the node.
sed -ie "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--node-labels=$k8s_labels |g" \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Determine the random 4 char suffix of the instance name, and then append
# that to the base k8s node name. The result should be a typical M-Lab node/DNS
# name with a "-<xxxx>" string on the end. With this, the node name is still
# unique, but we can easily just strip off the last 5 characters to get the name
# of the load balancer. Among other things, the uuid-annotator can use this
# value as its -hostname flag so that it knows how to annotate the data on this
# MIG instance.
node_suffix="${hostname##*-}"
node_name="${k8s_node}-${node_suffix}"

kubeadm join $lb_dns:6443 --token $token --discovery-token-ca-cert-hash $ca_cert_hash --node-name $node_name

# https://github.com/flannel-io/flannel/blob/master/Documentation/kubernetes.md#annotations
kubectl --kubeconfig /etc/kubernetes/kubelet.conf annotate node $node_name \
  flannel.alpha.coreos.com/public-ip-overwrite=$external_ip \
  --overwrite=true
