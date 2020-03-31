#!/bin/bash
#
# setup_stage1_usbs.sh generates per-machine USB images.
#
# setup_stage1_isos.sh should only be run after setup_stage1_minimal.sh has run
# successfully and the vmlinuz_stage1_minimal kernel is available.

SOURCE_DIR=$( dirname "${BASH_SOURCE[0]}" )
SOURCE_DIR=$( realpath "${SOURCE_DIR}" )

set -e

USAGE="$0 <project> <builddir> <outputdir> <configdir> <hostname-pattern>"
PROJECT=${1:?Please provide the GCP Project: $USAGE}
BUILD_DIR=${2:?Please specify a build directory: $USAGE}
OUTPUT_DIR=${3:?Please provide an output directory: $USAGE}
CONFIG_DIR=${4:?Please specify a config directory: $USAGE}

# Report all commands to log file (set -x writes to stderr).
set -xuo pipefail

# Use mlabconfig to fill in the template for every machine in the given
# PROJECT name.
pushd "${BUILD_DIR}"
  # TODO: Replace curl with a native go-get once mlabconfig is rewritten in Go.
  curl --location "https://raw.githubusercontent.com/m-lab/siteinfo/master/cmd/mlabconfig.py" > \
      ./mlabconfig.py
  mkdir -p "${OUTPUT_DIR}/scripts"
  python3 ./mlabconfig.py --format=server-network-config \
      --sites "${SITES}" \
      --physical \
      --project "${PROJECT}" \
      --label "project=${PROJECT}" \
      --template_input "${CONFIG_DIR}/create-stage1-usb-template.sh" \
     --template_output "${BUILD_DIR}/create-stage1-usb-{{hostname}}.sh"
popd

# Check whether there are any files in the glob pattern.
if ! compgen -G ${BUILD_DIR}/create-stage1-usb-*.sh ; then
  echo 'No files to build!'
  exit 0
fi

# Run each per-machine build script.
for create_usb_script in ${BUILD_DIR}/create-stage1-usb-*.sh ; do
  echo "${create_usb_script}"
  chmod 755 "${create_usb_script}"
  mkdir -p "${OUTPUT_DIR}/stage1_usbs"
  ${create_usb_script} "${SOURCE_DIR}" "${OUTPUT_DIR}" "${OUTPUT_DIR}/stage1_usbs"
done
