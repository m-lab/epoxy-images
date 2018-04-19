#!/bin/bash
#
# deploy.sh copies files and build artifacts from the local directory to a given
# GCS bucket. Copies are authorized using credentials found in the environment
# variable named by the given key name.
#
# deploy.sh is depends on the locations of build artifacts ($PWD/output) and
# action scripts ($PWD/actions).
#
# deploy.sh creates several directories in the given GCS $BUCKET:
#
# - /stage3_coreos
#   * coreos initramfs with epoxy_client and custom cloud-config.yaml
#   * coreos kernel, stock
#   * stage2 kernel with embedded initram image
#   * actions scripts for all stages
#
# - /stage3_mlxupdate
#   * debian-based initramfs with epoxy_client and Mellanox ROM update scripts
#   * debian kernel, stock
#   * stage2 kernel with embedded initram image
#   * actions scripts for all stages
#
# - /stage3_mlxupdate_iso
#   * stage3 mlxupdate bootable ISOs for first-time setup. (boot via DRAC)
#
# - /stage1_mlxrom
#   * stage1 mellanox ROMs, used by mlxupdate images
#
# Example:
#
#   # After a successful build phase:
#   ./deploy.sh SERVICE_ACCOUNT_mlab_sandbox gs://epoxy-mlab-sandbox

set -eux

SOURCE_DIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

USAGE="Usage: $0 <keyname> <gs://bucket>"
KEYNAME=${1:?Please provide the service account keyname: $USAGE}
BUCKET=${2:?Please provide the destination GCS bucket name: $USAGE}

# Verify BUCKET is in the correct format.
if [[ ${BUCKET:0:5} != "gs://" ]] ; then
  echo "Error: provide the destination GCS bucket in the form: gs://<bucket>"
  exit 1
fi

# TODO: use common stage2/ location; do not copy stage2_vmlinuz to stage3 dirs.

# Deploy all stage3_coreos images and actions.
${SOURCE_DIR}/travis/deploy_gcs.sh ${KEYNAME} \
  ${SOURCE_DIR}/output/stage2_vmlinuz \
  ${SOURCE_DIR}/output/coreos_custom_pxe_image.cpio.gz \
  ${SOURCE_DIR}/output/coreos_production_pxe.vmlinuz \
  ${SOURCE_DIR}/actions/stage2/stage1to2.ipxe \
  ${SOURCE_DIR}/actions/stage3_coreos/*.json \
  ${BUCKET}/stage3_coreos/

# Deploy all stage3_mlxupdate images and actions.
${SOURCE_DIR}/travis/deploy_gcs.sh ${KEYNAME} \
  ${SOURCE_DIR}/output/stage2_vmlinuz \
  ${SOURCE_DIR}/output/vmlinuz_stage3_mlxupdate \
  ${SOURCE_DIR}/output/initramfs_stage3_mlxupdate.cpio.gz \
  ${SOURCE_DIR}/actions/stage2/stage1to2.ipxe \
  ${SOURCE_DIR}/actions/stage3_mlxupdate/*.json \
  ${BUCKET}/stage3_mlxupdate/

# Deploy stage3_mlxupdate_iso images.
${SOURCE_DIR}/travis/deploy_gcs.sh ${KEYNAME} \
  ${SOURCE_DIR}/output/*.iso \
  ${BUCKET}/stage3_mlxupdate_iso/

# Deploy stage1_mlxrom images preserving version directory.
${SOURCE_DIR}/travis/deploy_gcs.sh ${KEYNAME} \
  ${SOURCE_DIR}/output/stage1_mlxrom/* \
  ${BUCKET}/stage1_mlxrom/

# Deploy stage1_mlxrom images again to the 'latest' directory (without version).
${SOURCE_DIR}/travis/deploy_gcs.sh ${KEYNAME} \
  ${SOURCE_DIR}/output/stage1_mlxrom/*/* \
  ${BUCKET}/stage1_mlxrom/latest/
