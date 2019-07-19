#!/bin/bash
#
# setup_stage1_isos.sh generates per-machine ISO images.
#
# setup_stage1_isos.sh should only be run after setup_stage2.sh has run
# successfully and the stage2_vmlinuz kernel is available.

SOURCE_DIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

set -e

USAGE="$0 <project> <builddir> <outputdir> <configdir> <hostname-pattern>"
PROJECT=${1:?Please provide the GCP Project: $USAGE}
BUILD_DIR=${2:?Please specify a build directory: $USAGE}
OUTPUT_DIR=${3:?Please provide an output directory: $USAGE}
CONFIG_DIR=${4:?Please specify a config directory: $USAGE}
HOSTNAMES=${5:?Please specify a hostname pattern: $USAGE}

# Report all commands to log file (set -x writes to stderr).
set -xuo pipefail

# Use mlabconfig to fill in the template for every machine matching the given
# HOSTNAMES pattern.
pushd ${BUILD_DIR}
  # TODO: Replace curl with a native go-get once mlabconfig is rewritten in Go.
  curl --location "https://raw.githubusercontent.com/m-lab/siteinfo/master/cmd/mlabconfig.py" > \
      ./mlabconfig.py
  mkdir -p ${OUTPUT_DIR}/scripts
  python ./mlabconfig.py --format=server-network-config \
      --physical \
      --select "${HOSTNAMES}" \
      --label "project=${PROJECT}" \
      --template_input "${CONFIG_DIR}/create-stage1-iso-template.sh" \
      --template_output "${BUILD_DIR}/create-stage1-iso-{{hostname}}.sh"

# Check whether there are any files in the glob pattern.
if ! compgen -G ${BUILD_DIR}/create-stage1-iso-*.sh ; then
  echo 'No images to build!'
  exit 0
fi

# Run each per-machine build script.
for create_iso_script in `ls ${BUILD_DIR}/create-stage1-iso-*.sh` ; do
  echo $create_iso_script
  chmod 755 $create_iso_script
  mkdir -p ${OUTPUT_DIR}/stage1_isos
  $create_iso_script ${SOURCE_DIR} ${OUTPUT_DIR} ${OUTPUT_DIR}/stage1_isos
done
