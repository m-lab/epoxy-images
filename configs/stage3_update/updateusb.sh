#!/bin/bash
#
# A small script to write an ISO image to a USB flash drive attached to an M-Lab node.

set -ux

ISO_FILE="${HOSTNAME}_stage1.iso"
PROJECT=""
USB_DEVICE=""

for field in $( cat /proc/cmdline ) ; do
  if [[ "epoxy.project" == "${field%%=*}" ]] ; then
    PROJECT=${field##epoxy.project=}
    break
  fi
done

if [[ -z ${PROJECT} ]]; then
  echo "ERROR: could not determine the GCP project. Giving up."
  exit 1
fi

# Construct the ISO URL.
iso_url="https://storage.googleapis.com/epoxy-${PROJECT}/stage1_isos/${HOSTNAME}_stage1.iso"

# Fetch the ISO from GCS.
wget ${iso_url}

# The previous wget command should deposit an ISO file in this directory. If
# for some reason it didn't then exit.
if ! [[ -f ${ISO_FILE} ]]; then
  echo "ERROR: Fetching the ISO image failed. Giving up."
  exit 1
fi

# The existing USB drive will already be formatted and at least one partition
# should be of type "vfat". No other disk on the system should have a partition
# type of "vfat".
USB_DEVICE=$(blkid | grep vfat | egrep -o '^\/dev\/sd[a-z]')

if [[ -z ${USB_DEVICE} ]]; then
  echo "ERROR: Unable to identify the device of the USB drive. Giving up."
  exit 1
fi

dd if=${ISO_FILE} of=${USB_DEVICE} bs=1M conv=fdatasync
