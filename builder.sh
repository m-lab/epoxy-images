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
  local regex_name="MLXROM_REGEXP_${PROJECT//-/_}"

  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  # For maximum flexibility, embed the root CA of all projects, as well as a
  # fallback to the Google Internet Authority intermediate cert used for GCS.
  TRUSTED_CERTS="${SOURCE_DIR}/configs/${target}/epoxy-ca.mlab-sandbox.pem"
  TRUSTED_CERTS+=",${SOURCE_DIR}/configs/${target}/epoxy-ca.mlab-staging.pem"
  TRUSTED_CERTS+=",${SOURCE_DIR}/configs/${target}/epoxy-ca.mlab-oti.pem"
  TRUSTED_CERTS+=",${SOURCE_DIR}/configs/${target}/gtsgiag3.pem"

  ${SOURCE_DIR}/setup_stage1.sh "${project}" "${builddir}" "${artifacts}" \
      "${SOURCE_DIR}/configs/${target}" "${!regex_name}" "${version}" \
      "${TRUSTED_CERTS}"

  rm -rf "${builddir}"
}

function stage1_bootstrapfs() {
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  ${SOURCE_DIR}/setup_stage1_bootstrapfs.sh \
      /go/bin/epoxy_client \
      ${artifacts}/bootstrapfs-MeasurementLabUpdate.tar.bz2

  rm -rf "${builddir}"
}

function stage2() {
  local target=${TARGET:?Please specify a target configuration name}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}

  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  ${SOURCE_DIR}/setup_stage2.sh "${builddir}" "${SOURCE_DIR}/vendor" \
     "${SOURCE_DIR}/configs/${target}" \
     "${artifacts}/stage2_initramfs.cpio.gz" \
     "${artifacts}/stage2_vmlinuz" \
      /go/bin/epoxy_client \
     "${SOURCE_DIR}/stage2.log" \
     "${SOURCE_DIR}/travis/one_line_per_minute.awk" \
  || (
     tail -100 ${SOURCE_DIR}/stage2.log && false
  )

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
      /go/bin/epoxy_client \
      http://stable.release.core-os.net/amd64-usr/${version}/coreos_production_pxe.vmlinuz \
      http://stable.release.core-os.net/amd64-usr/${version}/coreos_production_pxe_image.cpio.gz \
      "${artifacts}/coreos_custom_pxe_image.cpio.gz" &> ${SOURCE_DIR}/coreos.log \
  || (
      tail -100 ${SOURCE_DIR}/coreos.log && false
  )

  rm -rf ${builddir}
}

function stage3_mlxupdate() {
  local target=${TARGET:?Please specify a target configuration name}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  umask 0022
  install -D -m 644 ${SOURCE_DIR}/vendor/mft-4.4.0-44.tgz \
      ${builddir}/mft-4.4.0-44.tgz

  echo 'Starting stage3_mlxupdate build'
  ${SOURCE_DIR}/setup_stage3_mlxupdate.sh \
      ${builddir} ${artifacts} ${SOURCE_DIR}/configs/${target} \
      /go/bin/epoxy_client #&> ${SOURCE_DIR}/stage3_mlxupdate.log \
  #|| (
  #    tail -100 ${SOURCE_DIR}/stage3_mlxupdate.log && false
  #)

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
      /go/bin/epoxy_client

  rm -rf ${builddir}
}

function stage1_isos() {
  local target=${TARGET:?Please specify a target configuration name}
  local project=${PROJECT:?Please specify the PROJECT}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local regex_name="ISO_REGEXP_${PROJECT//-/_}"

  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  ${SOURCE_DIR}/setup_stage1_isos.sh "${project}" "${builddir}" "${artifacts}" \
      "${SOURCE_DIR}/configs/${target}" "${!regex_name}"

  rm -rf "${builddir}"
  return
}

function stage1_usbs() {
  local target=${TARGET:?Please specify a target configuration name}
  local project=${PROJECT:?Please specify the PROJECT}
  local artifacts=${ARTIFACTS:?Please define an ARTIFACTS output directory}
  local regex_name="USB_REGEXP_${PROJECT//-/_}"

  local builddir=$( mktemp -d -t build-${TARGET}.XXXXXX )

  ${SOURCE_DIR}/setup_stage1_usbs.sh "${project}" "${builddir}" "${artifacts}" \
      "${SOURCE_DIR}/configs/${target}" "${!regex_name}"

  rm -rf "${builddir}"
  return
}

mkdir -p ${ARTIFACTS}
case "${TARGET}" in
  stage1_mlxrom)
      stage1_mlxrom
      ;;
  stage1_bootstrapfs)
      stage1_bootstrapfs
      ;;
  stage1_minimal)
      stage1_minimal
      ;;
  stage1_isos)
      stage1_isos
      ;;
  stage1_usbs)
      stage1_usbs
      ;;
  stage2)
      stage2
      ;;
  stage3_coreos)
      stage3_coreos
      ;;
  stage3_mlxupdate)
      stage3_mlxupdate
      ;;
  *)
      echo "Unknown target: ${TARGET}"
      exit 1
      ;;
esac
