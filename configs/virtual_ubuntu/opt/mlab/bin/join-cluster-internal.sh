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

export PATH=$PATH:/opt/bin

# Collect data necessary to join the cluster.
external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/access-configs/0/external-ip")
hostname=$(hostname)
k8s_labels=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/k8s_labels")
lb_dns=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/lb_dns")
project=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/project-id")
token_server_dns=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/token_server_dns")

# Generate a JSON snippet suitable for the token-server, and then request a
# token.  https://github.com/m-lab/epoxy/blob/main/extension/request.go#L36
extension_v1="{\"v1\":{\"hostname\":\"${hostname}\",\"last_boot\":\"$(date --utc +%Y-%m-%dT%T.%NZ)\"}}"

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
  sleep 5
  token=$(curl --data "$extension_v1" "http://${token_server_dns}:8800/v1/allocate_k8s_token" || true)
done

# Fetch the ca_cert_hash stored in project metadata _after_ a token is
# retrieved. This will help to ensure that we are not fetching an outdated CA
# cert hash in the event that the control plane was reinitialized.
ca_cert_hash=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/platform_cluster_ca_hash")

# Set up necessary labels for the node.
sed -ie "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--node-labels=${k8s_labels} |g" \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Join the cluster.
kubeadm join "${lb_dns}:6443" --token $token --discovery-token-ca-cert-hash $ca_cert_hash --node-name $hostname

# https://github.com/flannel-io/flannel/blob/master/Documentation/kubernetes.md#annotations
kubectl --kubeconfig /etc/kubernetes/kubelet.conf annotate node $hostname \
  flannel.alpha.coreos.com/public-ip-overwrite=$external_ip \
  --overwrite=true

kubectl label node "$hostname" mlab/type=virtual
