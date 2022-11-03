# Common configuration for epoxy image builds. All builds source this file for
# relevant settings.

export SITES="https://siteinfo.${PROJECT}.measurementlab.net/v2/sites/sites.json"

# K8S component versions
export K8S_VERSION=v1.22.15
export K8S_CNI_VERSION=v1.1.1
export K8S_CRICTL_VERSION=v1.22.1
# v0.9.1 of the official CNI plugins release stopped including flannel, so we
# must now install it manually.
export K8S_FLANNELCNI_VERSION=v1.1.0

# stage3 mlxupdate
export MFT_VERSION=4.22.0-96

# multus-cni version
export MULTUS_CNI_VERSION=3.9
