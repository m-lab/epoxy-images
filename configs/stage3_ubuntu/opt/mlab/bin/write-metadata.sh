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

# Write out the metadata value for "managed". This will allow data users to know
# what environment the test was run. For a "full" site M-Lab manages both the
# machine and an upstream switch. For "minimal" deployments M-Lab only manages
# the machine, and nothing upstream.
PREFIX_LEN=$(egrep -o 'epoxy.ipv4=[^ ]+' /proc/cmdline | cut -d= -f2 | cut -d, -f1 | cut -d/ -f 2)
case "$PREFIX_LEN" in
  26)
    MANAGED="switch,machine"
    ;;
  28|29)
    MANAGED="machine"
    ;;
  *)
    echo "ERROR: cannot set MANAGED. Unknown prefix length ${PREFIX_LEN}"
    MANAGED="unknown"
    ;;
esac
echo -n "$MANAGED" > $METADATA_DIR/managed

# Physical machines are not loadbalanced.
echo -n "false" > $METADATA_DIR/loadbalanced

