#!/bin/bash
#
# build-iso-template.sh is a template bash script used by
# setup_stage3_mlxupdate_isos.sh to build per-machine Mellanox stage1 ROMs and
# stage3 mlxupdate ISO images, suitable for flashing the ROM during initial
# machine setup.
#
# Note: this script should execute within the epoxy-image builer docker image.
# Note: this script depends on the availability of the stage3_mlxupdate images.

set -e

BUILD_DIR=${1:?Please specify a build directory}
OUTPUT_DIR=${2:?Please provide an output directory}
SOURCE_DIR=${3:?Please provide the base source directory}
ROM_VERSION=${4:?Please provide the ROM version as "3.4.800"}
LOGFILE=${5:?Error: Please specify a path to write build log output}
FILTER=${6:?Error: Please specify a path for the travis output filter}

# Report all commands to log file (set -x writes to stderr).
exec 2> ${LOGFILE}
set -xuo pipefail

${SOURCE_DIR}/setup_stage1.sh \
    "{{project}}" "${BUILD_DIR}" "${OUTPUT_DIR}" \
    ${SOURCE_DIR}/configs/stage1_mlxrom \
    "{{hostname}}" "${ROM_VERSION}" \
    "${SOURCE_DIR}/configs/stage1_mlxrom/gtsgiag3.pem" 2>&1 \
    | tee -a ${LOGFILE} \
    | ${FILTER}


if [[ {{netmask}} != "255.255.255.192" ]] ; then
  echo 'Error: Sorry, unsupported netmask: {{netmask}}'
  exit 1
fi
mask=26

${SOURCE_DIR}/create_update_iso.sh \
    "{{project}}" "${BUILD_DIR}" "${OUTPUT_DIR}" "${ROM_VERSION}" \
    "{{hostname}}" "{{ip}}/${mask}" "{{gateway}}" "{{dns1}}" "8.8.4.4"
