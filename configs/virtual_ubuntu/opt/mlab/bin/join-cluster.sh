#!/bin/bash
#
# This script leverages the ePoxy boot server's "allocate_k8s_token" extension
# to fetch a cluster bootstrap token, and uses it to automatically join the
# M-Lab platform cluster.

set -euxo pipefail

export PATH=$PATH:/opt/bin

PROJECT=$(
  curl --silent -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/project/project-id"
)
FQDN=$(hostname --fqdn)
HOSTNAME=$(hostname)
API_SERVER="api-platform-cluster.${PROJECT}.measurementlab.net:6443"
STAGE1_URL="https://epoxy-boot-api.${PROJECT}.measurementlab.net/v1/boot/${FQDN}/stage1.json"
TOKEN_URL=$(
  curl --silent --location --request POST "$STAGE1_URL" | \
    jq -r '.kargs."epoxy.allocate_k8s_token"'
)
TOKEN=$(curl --silent --location --request POST "$TOKEN_URL")

gsutil cp "gs://epoxy-${PROJECT}/latest/stage3_ubuntu/setup_k8s.sh" /tmp/setup_k8s.sh
CA_HASH=$(egrep -o 'sha256:[[:alnum:]]+' /tmp/setup_k8s.sh)

# Set up necessary labels for the node.
NODE_LABELS="mlab/machine=${HOSTNAME:0:5},mlab/site=${HOSTNAME:6},mlab/metro=$(echo ${HOSTNAME:6:3}),mlab/type=virtual,mlab/run=ndt,mlab/project=${PROJECT}"
sed -ie "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--node-labels=$NODE_LABELS |g" \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

kubeadm join $API_SERVER --token $TOKEN --discovery-token-ca-cert-hash $CA_HASH --node-name $FQDN

EXTERNAL_IP=$(
  curl --silent -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip"
)
# https://github.com/flannel-io/flannel/blob/master/Documentation/kubernetes.md#annotations
kubectl --kubeconfig /etc/kubernetes/kubelet.conf annotate node $FQDN \
  flannel.alpha.coreos.com/public-ip-overwrite=${EXTERNAL_IP} \
  --overwrite=true
