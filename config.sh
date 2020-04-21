# Common configuration for epoxy image builds. All builds source this file for
# relevant settings.

# Use v2 sites.json for everything except mlab-oti.
if [[ "${PROJECT}" != "mlab-oti" ]]; then
  export SITES="https://siteinfo.${PROJECT}.measurementlab.net/v2/sites/sites.json"
else
  export SITES="https://siteinfo.${PROJECT}.measurementlab.net/v1/sites/sites.json"
fi

# stage3 coreos
export COREOS_VERSION=2303.4.0
export K8S_VERSION=v1.16.7
export CRI_VERSION=v1.18.0
export CNI_VERSION=v0.8.5

# stage3 mlxupdate
export MFT_VERSION=4.14.0-105

# stage1 mlxrom
export MLXROM_VERSION=3.4.817
