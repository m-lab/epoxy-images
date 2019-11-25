# Common configuration for epoxy image builds. All builds source this file for
# relevant settings.

# stage3 coreos
export COREOS_VERSION=2247.7.0
export K8S_VERSION=v1.15.6
export CRI_VERSION=v1.16.1
export CNI_VERSION=v0.8.3

# stage1 mlxrom
export MLXROM_VERSION=3.4.816
export MLXROM_REGEXP_mlab_sandbox='mlab[1-4].[a-z]{3}[0-9]t.*'
export MLXROM_REGEXP_mlab_staging='mlab4.[a-z]{3}[0-9]{2}.*'
export MLXROM_REGEXP_mlab_oti='mlab[1-3].[a-z]{3}[0-9]{2}.*'

# stage1 isos
export ISO_REGEXP_mlab_sandbox='mlab[1-4].[a-z]{3}[0-9]t.*'
export ISO_REGEXP_mlab_staging='mlab4.[a-z]{3}[0-9]{2}.*'
export ISO_REGEXP_mlab_oti='mlab[1-3].[a-z]{3}[0-9]{2}.*'
