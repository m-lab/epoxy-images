#!/bin/bash
#
# This script allows internal GCP cluster machines (e.g., the prometheus
# machine) to join the cluster by communicating directly with the token-server,
# which runs on every control plane machine. Regular, distributed platform
# cluster machines communicate with the token-server using ePoxy as a proxy. If
# a machine is already running on the private GCP VPC where the token-server is
# running, there is no need to proxy through ePoxy and the machine can
# communicate directly with the token-server on the private VPC network. The
# token-server does not do any sort of authentication, and relies on GCP
# firewall rules to block requests from untrusted sources.

set -euxo pipefail

METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

export KUBECONFIG="/etc/kubernetes/kubelet.conf"
export PATH=$PATH:/opt/bin

# Collect data necessary to join the cluster.
external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/access-configs/0/external-ip")
hostname=$(hostname)
k8s_labels=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/k8s_labels")
api_load_balancer=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/api_load_balancer")
project=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/project-id")
epoxy_extension_server=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/epoxy_extension_server")

# Generate a JSON snippet suitable for the token-server, and then request a
# token.  https://github.com/m-lab/epoxy/blob/main/extension/request.go#L36
extension_v1="{\"v1\":{\"hostname\":\"${hostname}\",\"last_boot\":\"$(date --utc +%Y-%m-%dT%T.%NZ)\"}}"

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
      "https://${api_load_balancer}:6443/readyz" \
      || true
  )
done

# Wait a while after the control plane is accessible on the API port, since in
# the case where the cluster is being initialized, there are a few housekeeping
# items to handle.
sleep 90

# Fetch cluster bootstrap join data from the ePoxy extension server.
join_data=$(
  curl --data "$extension_v1" "http://${epoxy_extension_server}:8800/v2/allocate_k8s_token" || true
)

if [[ -z $join_data ]]; then
  echo "Failed to get cluster bootstrap join data from the ePoxy extension server"
  exit 1
fi

# $join_data should contain a simple JSON block with all the information needed
# to join the cluster.
api_address=$(echo "$join_data" | jq -r '.api_address')
ca_hash=$(echo "$join_data" | jq -r '.ca_hash')
token=$(echo "$join_data" | jq -r '.token')

# Set up necessary labels for the node.
sed -ie "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--node-labels=${k8s_labels} |g" \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Join the cluster.
kubeadm join "$api_address" --token $token --discovery-token-ca-cert-hash $ca_hash --node-name $hostname

# https://github.com/flannel-io/flannel/blob/master/Documentation/kubernetes.md#annotations
kubectl annotate node $hostname \
  flannel.alpha.coreos.com/public-ip-overwrite=$external_ip \
  --overwrite=true

kubectl label node "$hostname" mlab/type=virtual
