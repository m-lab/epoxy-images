#!/bin/bash

set -euxo pipefail

# Create cache directory in root filesystem.
mkdir -p /cache

# Clear any remaining LVM configs from prior installations.
dmsetup remove_all --force

# Determine which sd* device we should use. Eliminate all hotplug device types,
# and then select the first disk that is greater than 250GB.
DEVICE=$(
  lsblk --output NAME,HOTPLUG,SIZE --bytes --json \
    | jq -r '[.blockdevices[] | select(.hotplug==false and .size>250000000000)][0] | .name'
)

# A minimal sanity check that discovering the device returned a valid device
# name.
if ! [[ $DEVICE =~ sd[a-z] ]]; then
  echo "ERROR: failed to identify the disk device name"
  exit 1
fi

# For a 1TB disk, this is roughly:
#  * 900G for core and experiment data.
#  * 100G for containerd image cache.
# Note: systemd translates double percent (%%) to a single percent.
parted --align=optimal --script /dev/$DEVICE \
  mklabel gpt \
  mkpart data xfs 0% 90% \
  mkpart containerd xfs 90% 100%

# There is potentially a delay between parted creating partitions and those
# partitions devices (e.g., /dev/sda1) showing in in /dev.
sleep 1

# Format and label each partition.
# Note: the labels could make the formatting conditional in the future.
/usr/sbin/mkfs.xfs -f -L data /dev/${DEVICE}1
/usr/sbin/mkfs.xfs -f -L containerd /dev/${DEVICE}2

