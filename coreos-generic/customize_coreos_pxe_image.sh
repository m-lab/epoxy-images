#!/bin/bash
#
# customize_coreos_pxe_image.sh downloads the current stable coreos pxe images
# and generates a modified image that embeds custom scripts and static
# cloud-config.yml. These custom scripts conigure the static network IP and
# allow for running a post-boot setup script.

set -e
set -x
OUTPUT=${1:?Please provide the name of the output image}
BASEDIR=$( dirname "${BASH_SOURCE[0]}" )

# Convert relative path to an absolute path.
BASEDIR=$( readlink -f $BASEDIR )
OUTPUT=$( readlink -f $OUTPUT )

# Download CoreOS images.
URL=http://stable.release.core-os.net/amd64-usr/current
pushd build
  for file in coreos_production_pxe.vmlinuz \
              coreos_production_pxe_image.cpio.gz ; do
    test -f $file || curl -O ${URL}/${file}
  done
popd


pushd build
  # Unpack the cpio and squashfs image.
  ORIGINAL=${PWD}/coreos_production_pxe_image.cpio.gz
  mkdir -p initrd
  pushd initrd
      gzip -d --to-stdout ${ORIGINAL} | cpio -i
  popd
  unsquashfs initrd/usr.squashfs

  # Copy resources to the "/usr/share/oem" directory.
  cp -ar ${BASEDIR}/resources/* squashfs-root/share/oem/

  # Rebuild the squashfs and cpio image.
  mksquashfs squashfs-root initrd/usr.squashfs -noappend -always-use-fragments
  pushd initrd
    find . | cpio -o -H newc | gzip > "${OUTPUT}"
  popd

  # Cleanup
  rm -rf squashfs-root
  rm -rf initrd
popd
