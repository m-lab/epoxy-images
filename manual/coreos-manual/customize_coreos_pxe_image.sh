#!/bin/bash

set -e
set -x
CONFIG=${1:?Please provide a config file to copy into output image}
OUTPUT=${2:?Please provide the name of the output image}

# Download CoreOS images.
URL=http://stable.release.core-os.net/amd64-usr/current
curl -O ${URL}/coreos_production_pxe.vmlinuz
curl -O ${URL}/coreos_production_pxe_image.cpio.gz


# Unpack the cpio and squashfs image.
ORIGINAL=$PWD/coreos_production_pxe_image.cpio.gz
cp ${ORIGINAL} custom.cpio.gz
mkdir -p initrd
pushd initrd
    gzip -d --to-stdout ${ORIGINAL} | cpio -i
popd
sudo unsquashfs initrd/usr.squashfs
sudo cp ${CONFIG} squashfs-root/share/oem/cloud-config.yml

# Rebuild the squashfs and cpio image.
sudo mksquashfs $PWD/squashfs-root initrd/usr.squashfs -noappend -always-use-fragments
pushd initrd
  sudo find . | cpio -o -H newc | gzip > $OUTPUT
popd

# Cleanup
sudo rm -rf squashfs-root
sudo rm -rf initrd
