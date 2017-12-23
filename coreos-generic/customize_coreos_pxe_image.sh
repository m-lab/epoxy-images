#!/bin/bash
#
# customize_coreos_pxe_image.sh downloads the current stable coreos pxe images
# and generates a modified image that embeds custom scripts and static
# cloud-config.yml. These custom scripts conigure the static network IP and
# allow for running a post-boot setup script.

set -e
set -x
VMLINUZ_URL=${1:?Please provide the URL for a coreos vmlinuz image}
INITRAM_URL=${2:?Please provide the URL for a coreos initram image}
CUSTOM=${3:?Please provide the name for writing a customized initram image}

SCRIPTDIR=$( dirname "${BASH_SOURCE[0]}" )

# Convert relative path to an absolute path.
SCRIPTDIR=$( readlink -f $SCRIPTDIR )
CUSTOM=$( readlink -f $CUSTOM )
IMAGEDIR=$( dirname $CUSTOM )

mkdir -p $IMAGEDIR
pushd $IMAGEDIR
  # Download CoreOS images.
  for url in $VMLINUZ_URL $INITRAM_URL ; do
    file=$( basename $url )
    test -f $file || curl -O ${url}
  done

  # Uncompress and unpack the cpio image.
  ORIGINAL=${PWD}/$( basename $INITRAM_URL )
  mkdir -p initrd-contents
  pushd initrd-contents
      gzip -d --to-stdout ${ORIGINAL} | cpio -i
  popd

  # Extract the squashfs into a default dir name 'squashfs-root'
  # Note: xattrs do not work within a docker image, they are not necessary.
  unsquashfs -no-xattrs initrd-contents/usr.squashfs

  # Copy resources to the "/usr/share/oem" directory.
  cp -a ${SCRIPTDIR}/resources/* squashfs-root/share/oem/

  # Rebuild the squashfs and cpio image.
  mksquashfs squashfs-root initrd-contents/usr.squashfs \
      -noappend -always-use-fragments

  pushd initrd-contents
    find . | cpio -o -H newc | gzip > "${CUSTOM}"
  popd

  # Cleanup
  rm -rf initrd-contents
  rm -rf fake-usr
popd
