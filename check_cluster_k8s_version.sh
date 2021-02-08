#!/bin/bash

source ./config.sh

# Check k8s cluster version to be sure that it is equal to the configured k8s
# version in this repo (config.sh) before continuing.
CLUSTER_VERSION=$(
  curl --insecure --silent \
    https://api-platform-cluster.$PROJECT.measurementlab.net:6443/version \
    | jq -r '.gitVersion'
)
if [[ $CLUSTER_VERSION != $K8S_VERSION ]]; then
  echo "Cluster k8s version is ${CLUSTER_VERSION}, but configured k8s version in this repo is ${K8S_VERSION}. Exiting..."
  exit 1
fi

