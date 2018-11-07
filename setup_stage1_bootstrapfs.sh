#!/bin/bash
#
# setup_stage1_bootstrapfs.sh creates a pseudo-bootstrapfs for a modified
# PlanetLab BootManager.

set -x
set -e

SOURCE_DIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

USAGE="$0 <build_dir> <output_dir> <config_dir>"
BUILD_DIR=${1:?Please specify a build directory: $USAGE}
EPOXY_CLIENT=${2:?Please specify the path to the epoxy client binary: $USAGE}
CONFIG_DIR=${3:?Please specify a configuration directory: $USAGE}
OUTPUT_DIR=${4:?Please specify an output directory: $USAGE}

# TODO: implement bootstrapfs build.
#
# Steps:
# * make tmp dir
# * create dir tree
# * copy epoxy client to tmpdir
# * tar bz2 content of tmp dir
# * copy result to output_dir

