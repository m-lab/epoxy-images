# Common configuration for epoxy image builds. All builds source this file for
# relevant settings.

export SITES="https://siteinfo.${PROJECT}.measurementlab.net/v2/sites/sites.json"

# K8S component versions
export K8S_VERSION=v1.20.13
export K8S_CNI_VERSION=v1.0.1
export K8S_CRICTL_VERSION=v1.20.0

# stage3 mlxupdate
export MFT_VERSION=4.14.0-105

# stage1 mlxrom
export MLXROM_VERSION=3.4.817

# multus-cni version
export MULTUS_CNI_VERSION=3.8
