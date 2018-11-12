#!/bin/bash
#
# setup_stage1_bootstrapfs.sh creates a pseudo-bootstrapfs for a modified
# PlanetLab BootManager.

set -x
set -e

SOURCE_DIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

USAGE="$0 <epoxy-client> <output_file>"
EPOXY_CLIENT=${1:?Please specify the path to the epoxy client binary: $USAGE}
OUTPUT_FILE=${2:?Please specify an output file: $USAGE}

# Create a custom bootstrapfs.
output=$( mktemp -d -t build-bootstrapfs.XXXXX )
mkdir -p ${output}/{etc,usr/bin,boot}
install -D -m 755 "${EPOXY_CLIENT}" "${output}/epoxy_client"
tar -C "${output}" -jcvf "${OUTPUT_FILE}" .
cat "${OUTPUT_FILE}" | shasum > "${OUTPUT_FILE}".sha1sum
rm -rf "${output}"
