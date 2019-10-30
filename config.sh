# Common configuration for epoxy image builds. All builds source this file for
# relevant settings.

# stage3 coreos
COREOS_VERSION=2247.5.0
K8S_VERSION=v1.14.8
CRI_VERSION=v1.16.1
CNI_VERSION=v0.8.2

# stage1 mlxrom
MLXROM_VERSION=3.4.816
MLXROM_REGEXP_mlab_sandbox='mlab[1-4].[a-z]{3}[0-9]t.*'
MLXROM_REGEXP_mlab_staging='mlab4.[a-z]{3}[0-9]{2}.*'
MLXROM_REGEXP_mlab_oti='mlab[1-3].[a-z]{3}[0-9]{2}.*'

# stage1 isos
ISO_REGEXP_mlab_sandbox='mlab[1-4].[a-z]{3}[0-9]t.*'
ISO_REGEXP_mlab_staging='mlab4.[a-z]{3}[0-9]{2}.*'
ISO_REGEXP_mlab_oti='mlab[1-3].[a-z]{3}[0-9]{2}.*'
