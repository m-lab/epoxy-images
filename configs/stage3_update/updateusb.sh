#!/bin/bash
#
# A small script to write an ISO image to a USB flash drive attached to an M-Lab node.

set -eux

ISO_BACKUP="usb_backup.iso"
ISO_FILE="${HOSTNAME}_stage1.iso"
HEADERS_FILE="iso_headers"
USB_DEVICE=""
TEMPDIR=$(mktemp --directory)

trap "rm -rf ${TEMPDIR}" EXIT

pushd ${TEMPDIR}

iso_url=""
for field in $( cat /proc/cmdline ) ; do
  if [[ "epoxy.usbiso" == "${field%%=*}" ]] ; then
    iso_url=${field##epoxy.usbiso=}
    break
  fi
done

if [[ -z ${iso_url} ]]; then
  echo "ERROR: could not find the ISO URL in the kernel params. Giving up."
  exit 1
fi

# Fetch the ISO from GCS.
curl --silent --remote-name --dump-header ${HEADERS_FILE} ${iso_url}

# The previous wget command should deposit an ISO file in this directory. If
# for some reason it didn't then exit.
if ! [[ -f ${ISO_FILE} ]]; then
  echo "ERROR: Fetching the ISO image failed. Giving up."
  exit 1
fi

# Extract the md5 hash from the request. It appears that curl writes out the
# headers file using \r\n for newlines. The extra "tr" is to strip off the
# remaining \r.
md5_actual=$(grep "x-goog-hash: md5" ${HEADERS_FILE} | cut -d= -f2- | tr -d '\r')

# Calculate the md5 locally.
md5_calc=$(openssl dgst -md5 -binary ${ISO_FILE} | openssl enc -base64)

# Compare the md5 hashes.
if [[ $md5_actual != $md5_calc ]]; then
  echo "ERROR: the md5 hash of the file does not match the x-goog-hash header."
  exit 1
fi

# The existing USB drive will already be formatted and at least one partition
# should be of type "vfat". No other disk on the system should have a partition
# type of "vfat".
USB_DEVICE=$(/usr/sbin/blkid | grep vfat | egrep -o '^\/dev\/sd[a-z]')

if [[ -z ${USB_DEVICE} ]]; then
  echo "ERROR: Unable to identify the device of the USB drive. Giving up."
  exit 1
fi

# Make a backup of the existing ISO on the USB. Our stage1 ISOs are currently
# only around 450MB, so stop pulling data from the drive at 600MB, else we will
# fill up the root filesystem and waste time.
dd if=${USB_DEVICE} of=${ISO_BACKUP} bs=1M count=600

# Get the ISO partition details.
iso_parts=$(/usr/sbin/fdisk -l ${ISO_FILE} | grep "^${ISO_FILE}" | awk '{$1=""; print $0}')

# Write the new ISO.
dd if=${ISO_FILE} of=${USB_DEVICE} bs=1M conv=fdatasync

# Get the partition details of the USB.
usb_parts=$(/usr/sbin/fdisk -l ${USB_DEVICE} | grep "^${USB_DEVICE}" | awk '{$1=""; print $0}')

# Make sure that the ISO partition details match those written to the USB.
if [[ $usb_parts != $iso_parts ]]; then
  echo "ERROR: ISO partition details to not match those wriiten to the USB drive."
  echo "Attempting to restore the original ISO backup to the USB drive."
  dd if=${ISO_BACKUP} of=${USB_DEVICE} bs=1M conv=fdatasync
  exit 1
fi

popd
