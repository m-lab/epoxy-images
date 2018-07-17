#!/bin/bash
#
# setup_stage3_mlxupdate_isos.sh generates per-machine Mellanox ROM and
# stage3_mlxupdate ISO images.
#
# setup_stage3_mlxupdate_isos.sh should only be run after
# setup_stage3_mlxupdate.sh has run successfully and the stage3_mlxupdate image
# and kernel are available.

SOURCE_DIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

set -e

USAGE="$0 <builddir> <outputdir> <hostname-pattern> <version>"
PROJECT=${1:?Please provide the GCP Project}
BUILD_DIR=${2:?Please specify a build directory: $USAGE}
OUTPUT_DIR=${3:?Please provide an output directory}
HOSTNAMES=${4:?Please specify a hostname pattern: $USAGE}
ROM_VERSION=${5:?Please provide the ROM version as "3.4.800"}
LOGFILE=${6:?Error: Please specify a path to write build log output}
FILTER=${7:?Error: Please specify a path for the travis output filter}

# Report all commands to log file (set -x writes to stderr).
exec 2> ${LOGFILE}
set -xuo pipefail

# Use mlabconfig and the build-iso-template.sh to generate per-machine ROM and
# ISO build scripts.
pushd ${BUILD_DIR}
  test -d operator || git clone https://github.com/m-lab/operator
  pushd operator/plsync
    mkdir -p ${OUTPUT_DIR}/scripts
    ./mlabconfig.py --format=server-network-config \
        --select "${HOSTNAMES}" \
        --label "project=${PROJECT}" \
        --template_input "${SOURCE_DIR}/configs/stage1_mlxrom/build-iso-template.sh" \
        --template_output "${OUTPUT_DIR}/scripts/build-iso-{{hostname}}.sh"
  popd
popd

# Run each per-machine build script.
for script in `ls ${OUTPUT_DIR}/scripts/build-iso-*.sh` ; do
  echo $script
  chmod 755 $script
  $script ${BUILD_DIR} ${OUTPUT_DIR} ${SOURCE_DIR} "${ROM_VERSION}" ${LOGFILE} \
      ${FILTER}
done
