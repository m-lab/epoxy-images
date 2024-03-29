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
epoxy_extension_server=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/epoxy_extension_server")
external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/access-configs/0/external-ip")
internal_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/ip")
hostname=$(hostname)
k8s_labels=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/k8s_labels")
k8s_node=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/k8s_node")
api_load_balancer=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/api_load_balancer")
project=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/project-id")

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

# Generate a JSON snippet suitable for the ePoxy extension server, and then
# request a token.
# https://github.com/m-lab/epoxy/blob/main/extension/request.go#L36
extension_v1="{\"v1\":{\"hostname\":\"${hostname}\",\"last_boot\":\"$(date --utc +%Y-%m-%dT%T.%NZ)\"}}"

# Fetch cluster bootstrap join data from the ePoxy extension server.
#
# TODO (kinkade): here we are querying the ePoxy extension server directly
# through the GCP private network. This only works from within GCP, so is not a
# long term solution. It is just a stop-gap to get GCP VMs able to join the
# cluster until we have implemented a more global solution that will support
# any cloud provider. Additionally, going through ePoxy will not work for VMs
# in a managed instance group (MIG), since siteinfo, ePoxy and Locate will only
# know about the load balancer IP address, not the possibly ephemeral public IP
# of an auto-scaled instance in a MIG.
join_data=$(
  curl --data "$extension_v1" "http://${epoxy_extension_server}:8800/v2/allocate_k8s_token" || true
)

if [[ -z $join_data ]]; then
  echo "Failed to get cluster bootstrap join data from the epoxy-extension-server"
  exit 1
fi

# $JOIN_DATA should contain a simple JSON block with all the information needed
# to join the cluster.
api_address=$(echo "$join_data" | jq -r '.api_address')
ca_hash=$(echo "$join_data" | jq -r '.ca_hash')
token=$(echo "$join_data" | jq -r '.token')

# Regarding the --node-ip flag below, for some reason I have not figured out,
# on dual stack VMs the kubelet selects the IPv6 address for the InternalIP
# field, which causes all sorts of breakage. Here we pass the internal IP
# address of the VM as a flag to the kubelet so that it assigns the right
# InternalIP. From what I can tell in my research this has something to do with
# running the kubelet in a cloud environment but without any cloud controller
# manager in the cluster.
#
# Add an env variable to the kubelet drop-in file and then append that env
# variable to the ExecStart line.
echo "Environment=\"MLAB_EXTRA_ARGS=--node-ip=${internal_ip} --node-labels=${k8s_labels} \"" \
  >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i '/ExecStart=\// s/$/ $MLAB_EXTRA_ARGS/' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Set the system's hostname to the node name. By default, kubeadm uses the
# hostname for the node name. The hostname, as defined in the instance's
# hostname metadata field, is the FQDN. However, some machinery in the Google
# guest package sets the system's hostname to just the first part of the FQDN.
# Take this opportunity to set the system's hostname to whatever we think the
# k8s node  name should be, such that kubeadm picks up the right name by
# default. We don't want to use the kubeadm --node-name flag, because when you
# do, kubeadm will refuse to join the node to the cluster if there is already a
# node of that name.
hostnamectl set-hostname $node_name

# This script is run by the join-cluster.service systemd unit, and it set to
# Restart=Always. In some cases kubeadm may start to run but fail for various,
# possibly ephemeral, reasons. When this happens, kubeadm may fail preflight
# checks because it finds certain files already exist. For this reason we add
# --ignore-preflight-errors=all in order to unconditionally try to join the
# cluster as many times as this scripts gets run.
kubeadm join "$api_address"  --v 4  --token "$token" \
  --discovery-token-ca-cert-hash "$ca_hash" --ignore-preflight-errors all

# https://github.com/flannel-io/flannel/blob/master/Documentation/kubernetes.md#annotations
kubectl --kubeconfig /etc/kubernetes/kubelet.conf annotate node $node_name \
  flannel.alpha.coreos.com/public-ip-overwrite=$external_ip \
  --overwrite=true

