#!/bin/bash
#
# Note: this script should execute within the epoxy-image builer docker image.

BUILD_DIR=${1:?Please specify a build directory}
OUTPUT_DIR=${2:?Please provide an output directory}
SOURCE_DIR=${3:?Please provide the base source directory}
ROM_VERSION=${4:?Please provide the ROM version as "3.4.800"}

./setup_stage1.sh \
    "${BUILD_DIR}" "${OUTPUT_DIR}" ${SOURCE_DIR}/configs/stage1_mlxrom \
    "{{hostname}}" "${ROM_VERSION}" "${SOURCE_DIR}/configs/stage1_mlxrom/giag2.pem"

if [[ {{netmask}} != "255.255.255.192" ]] ; then
  echo 'Error: Sorry, unsupported netmask: {{netmask}}'
  exit 1
fi
mask=26

./create_update_iso.sh \
    "${BUILD_DIR}" "${OUTPUT_DIR}" "${ROM_VERSION}" \
    "{{hostname}}" "{{ip}}/${mask}" "{{gateway}}" "{{dns1}}" "8.8.4.4"
