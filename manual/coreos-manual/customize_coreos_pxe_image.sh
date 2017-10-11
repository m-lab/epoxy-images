#!/bin/bash

set -e
set -x
# ORIGINAL=${1:?Please provide an unmodified CoreOS PXE CPIO image}
CONFIG=${1:?Please provide a config file to copy into output image}
OUTPUT=${2:?Please provide the name of the output image}

URL=http://stable.release.core-os.net/amd64-usr/current
curl -O ${URL}/coreos_production_pxe.vmlinuz
curl -O ${URL}/coreos_production_pxe_image.cpio.gz


ORIGINAL=$PWD/coreos_production_pxe_image.cpio.gz
cp ${ORIGINAL} custom.cpio.gz
mkdir -p initrd
pushd initrd
    gzip -d --to-stdout ${ORIGINAL} | cpio -i
popd

sudo unsquashfs initrd/usr.squashfs
sudo cp ${CONFIG} squashfs-root/share/oem/cloud-config.yml

# Rebuild squashfs image and the cpio images.
sudo mksquashfs $PWD/squashfs-root initrd/usr.squashfs -noappend -always-use-fragments
pushd initrd
  sudo find . | cpio -o -H newc | gzip > $OUTPUT
popd

# Cleanup
sudo rm -rf squashfs-root
sudo rm -rf initrd
