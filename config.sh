# Common configuration for epoxy image builds. All builds source this file for
# relevant settings.
#
# NOTE: these values should be kept in sync with the corresponding variables in
# k8s-support. TODO(kinkade): we need a better way to manage these values.
#
# https://github.com/m-lab/k8s-support/blob/main/manage-cluster/k8s_deploy.conf#L31

export SITES="https://siteinfo.${PROJECT}.measurementlab.net/v2/sites/sites.json"

# K8S component versions
export K8S_VERSION=v1.27.12
export K8S_CNI_VERSION=v1.4.1
export K8S_CRICTL_VERSION=v1.27.1
# v0.9.1 of the official CNI plugins release stopped including flannel, so we
# must now install it manually.
export K8S_FLANNELCNI_VERSION=v1.4.0-flannel1
export K8S_TOOLING_VERSION=v0.16.7

# stage3 mlxupdate
export MFT_VERSION=4.22.0-96

# stage1 mlxrom
export MLXROM_VERSION=3.4.818

# multus-cni version
export MULTUS_CNI_VERSION=3.9.3

# etcdctl version
export ETCDCTL_VERSION=v3.5.12
