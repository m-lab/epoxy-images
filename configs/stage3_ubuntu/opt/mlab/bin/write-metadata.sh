#!/bin/bash
#
# This script writes various pieces of metadata to files in a known location.
# This directory can be mounted into experiment pods so that the experiment can
# have some awareness of its environment. The experiment may optionally include
# this metadata in its test results.

$METADATA_DIR=/var/local/metadata

mkdir -p /var/local/metadata

# Write the kernel version
uname -r | tr -d '\n' > $METADATA_DIR/kernel-version

