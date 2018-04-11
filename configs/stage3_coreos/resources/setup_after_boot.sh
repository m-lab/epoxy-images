#!/bin/bash
#
# setup_after_boot.sh will run after boot and only once the network is online.
# The script runs as the root user.

# Log all output.
exec 2> /var/log/setup_after_boot.log 1>&2

# Stop on any failure.
set -euxo pipefail

mkdir -p /cache

# Report start time.
date

# Clear any remaining LVM configs from prior installations.
/usr/sbin/dmsetup remove_all --force

# Repartition disk

# For a 500GB disk, this is roughly:
#  * 250G for experiment data.
#  * 150G for core experiment data.
#  * 100G for docker image cache.
/usr/sbin/parted --align=optimal \
    --script /dev/sda \
    mklabel gpt \
    mkpart data ext4 0% 50% \
    mkpart core ext4 50% 80% \
    mkpart docker ext4 80% 100%

# Format and label each partition.
# Note: the labels could make the formatting conditional in the future.
/usr/sbin/mke2fs -t ext4 -F -L cache-data /dev/sda1
/usr/sbin/mke2fs -t ext4 -F -L cache-core /dev/sda2
/usr/sbin/mke2fs -t ext4 -F -L cache-docker /dev/sda3

# Actually mount.
systemctl start cache-data.mount
systemctl start cache-core.mount
systemctl start cache-docker.mount

# Report end format time.
date

echo "Running epoxy client"
/usr/bin/epoxy_client -action epoxy.stage3
