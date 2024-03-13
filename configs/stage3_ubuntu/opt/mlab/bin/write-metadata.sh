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
# the machine, and nothing upstream. For bring-your-own-server (BYOS) M-Lab
# manages nothing. The /32 case is supposed to represent BYOS, though as this is
# written it's not clear whether this script in this repository will even be
# present in those container images.
PREFIX_LEN=$(ip -family inet -json addr show dev eth0 | jq '.[0].addr_info[0].prefixlen')
case "$PREFIX_LEN" in
  26)
    MANAGED="switch,machine"
    ;;
  28|29)
    MANAGED="machine"
    ;;
  32)
    MANAGED="none"
    ;;
  *)
    echo "ERROR: cannot set MANAGED. Unknown prefix length ${PREFIX_LEN}"
    MANAGED="unknown"
    ;;
esac
echo -n "$MANAGED" > $METADATA_DIR/managed
