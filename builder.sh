#!/bin/bash
#
# builder.sh should be called by cloudbuilder.yaml. builder accepts a single
# parameter (target) and multiple parameters from the environment. builder.sh
# transalates these into calls to specific build scripts.

set -eu
SOURCE_DIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

source "${SOURCE_DIR}/config.sh"

USAGE="$0 <target>"
TARGET=${1:?Please provide a build target: $USAGE}

function stage1_mlxrom() {
  local target=${TARGET:?Please specify a target configuration name}
  local project=${PROJECT:?Please specify the PROJECT}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local version=${MLXROM_VERSION:?Please define the MLXROM_VERSION to build}

  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  # For maximum flexibility, embed the root CA of all projects, as well as a
  # fallback to the Google Internet Authority intermediate cert used for GCS.
  TRUSTED_CERTS="${SOURCE_DIR}/configs/${target}/epoxy-ca.mlab-sandbox.pem"
  TRUSTED_CERTS+=",${SOURCE_DIR}/configs/${target}/epoxy-ca.mlab-staging.pem"
  TRUSTED_CERTS+=",${SOURCE_DIR}/configs/${target}/epoxy-ca.mlab-oti.pem"
  TRUSTED_CERTS+=",${SOURCE_DIR}/configs/${target}/gtsgiag3.pem"

  ${SOURCE_DIR}/setup_stage1_mlxrom.sh "${project}" "${builddir}" "${artifacts}" \
      "${SOURCE_DIR}/configs/${target}" "${version}" "${TRUSTED_CERTS}"

  rm -rf "${builddir}"
}

# Build coreos custom initram image.
function stage3_coreos() {
  local target=${TARGET:?Please specify a target configuration name}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local version=${COREOS_VERSION:?Please specify the coreos version}
  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  umask 0022
  ${SOURCE_DIR}/setup_stage3_coreos.sh \
      "${SOURCE_DIR}/configs/${target}" \
      /root/go/bin/epoxy_client \
      http://stable.release.core-os.net/amd64-usr/${version}/coreos_production_pxe.vmlinuz \
      http://stable.release.core-os.net/amd64-usr/${version}/coreos_production_pxe_image.cpio.gz \
      "${artifacts}/coreos_custom_pxe_image.cpio.gz" &> ${SOURCE_DIR}/coreos.log \
  || (
      tail -100 ${SOURCE_DIR}/coreos.log && false
  )

  rm -rf ${builddir}
}

function stage3_update() {
  local target=${TARGET:?Please specify a target configuration name}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  umask 0022
  echo 'Starting stage3_update build'
  ${SOURCE_DIR}/setup_stage3_update.sh \
      ${builddir} ${artifacts} ${SOURCE_DIR}/configs/${target} \
      /root/go/bin/epoxy_client &> ${SOURCE_DIR}/stage3_update.log \
  || (
      tail -100 ${SOURCE_DIR}/stage3_update.log && false
  )

  rm -rf ${builddir}
}

function stage1_minimal() {
  local target=${TARGET:?Please specify a target configuration name}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  umask 0022
  echo 'Starting stage1_minimal build'
  ${SOURCE_DIR}/setup_stage1_minimal.sh \
      ${builddir} ${artifacts} ${SOURCE_DIR}/configs/${target} \
      /root/go/bin/epoxy_client

  rm -rf ${builddir}
}

function stage3_ubuntu() {
  local target=${TARGET:?Please specify a target configuration name}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  umask 0022
  echo 'Starting stage3_ubuntu build'
  ${SOURCE_DIR}/setup_stage3_ubuntu.sh \
      ${builddir} ${artifacts} ${SOURCE_DIR}/configs/${target} \
      /root/go/bin/epoxy_client

  rm -rf ${builddir}
}

function packer_images() {
  echo 'Starting packer_images build'
  ${SOURCE_DIR}/setup_packer_images.sh
}

function stage1_isos() {
  local target=${TARGET:?Please specify a target configuration name}
  local project=${PROJECT:?Please specify the PROJECT}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}

  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  ${SOURCE_DIR}/setup_stage1_isos.sh "${project}" "${builddir}" "${artifacts}" \
      "${SOURCE_DIR}/configs/${target}"

  rm -rf "${builddir}"
  return
}

mkdir -p ${ARTIFACTS}
case "${TARGET}" in
  stage1_mlxrom)
      stage1_mlxrom
      ;;
  stage1_minimal)
      stage1_minimal
      ;;
  stage1_isos)
      stage1_isos
      ;;
  stage3_coreos)
      stage3_coreos
      ;;
  stage3_ubuntu)
      stage3_ubuntu
      ;;
  packer_images)
      packer_images
      ;;
  stage3_update)
      stage3_update
      ;;
  *)
      echo "Unknown target: ${TARGET}"
      exit 1
      ;;
esac
