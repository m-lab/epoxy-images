#!/bin/bash
#
# This script writes various pieces of metadata to files in a known location.
# This directory can be mounted into experiment pods so that the experiment can
# have some awareness of its environment. The experiment may optionally include
# this metadata in its test results.

METADATA_DIR=/var/local/metadata
mkdir -p $METADATA_DIR

# Write the kernel version
uname -r | tr -d '\n' > $METADATA_DIR/kernel-version

# Write the hostname to a file, which will be used by uuid-annotator to
# determine which node name to use from the annotations.json file. It cannot use
# hostname directly because hostnames and node names on virtual nodes do not
# match entries in siteinfo. The virtual machines are part of managed instance
# groups in a region, and they all have unique non-deterministic names. Both
# physical and virtual nodes will this metadata file to provide a common
# interface for uuid-annotator.
hostname | tr -d '\n' > $METADATA_DIR/node-name
