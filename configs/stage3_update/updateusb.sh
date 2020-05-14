#!/bin/bash
#
# A small script to write an ISO image to a USB flash drive attached to an M-Lab node.

set -ux

ISO_FILE="${HOSTNAME}_stage1.iso"

for field in $( cat /proc/cmdline ) ; do
  if [[ "epoxy.usbiso" == "${field%%=*}" ]] ; then
    isourl=${field##epoxy.usbiso=}
    break
  fi
done

if [[ -z ${isourl} ]]; then
  echo "ERROR: no ISO URL found. Giving up."
  exit 1
fi

# Fetch the ISO from GCS.
wget ${isourl}

# The previouis wget command should deposit an ISO file in this directory. If
# for some reason it didn't then exit.
if ! [[ -f ${ISO_FILE} ]]; then
  echo "ERROR: Fetching the ISO image failed. Giving up."
  exit 1
fi

# The existing USB drive will already be formatted and at least one partition
# should be of type "vfat". No other disk on the system should have a partition
# type of "vfat".
usb_device=$(blkid | grep vfat | egrep -o '^\/dev\/sd[a-z]')

if [[ -z $usb_device ]]; then
  echo "ERROR: Unable to identify the device of the USB drive. Giving up."
  exit 1
fi

dd if=${ISO_FILE} of=${usb_device} bs=1M conv=fdatasync
