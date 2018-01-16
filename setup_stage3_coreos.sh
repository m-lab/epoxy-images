#!/bin/bash
#
# customize_coreos_pxe_image.sh downloads the current stable coreos pxe images
# and generates a modified image that embeds custom scripts and static
# cloud-config.yml. These custom scripts conigure the static network IP and
# allow for running a post-boot setup script.

set -e
set -x
USAGE="USAGE: $0 <config dir> <vmlinuz-url> <initram-url> <custom-initram-name>"
CONFIG_DIR=${1:?Please specify path to configuration directory: $USAGE}
VMLINUZ_URL=${2:?Please provide the URL for a coreos vmlinuz image: $USAGE}
INITRAM_URL=${3:?Please provide the URL for a coreos initram image: $USAGE}
CUSTOM=${4:?Please provide the name for a customized initram image: $USAGE}

SCRIPTDIR=$( dirname "${BASH_SOURCE[0]}" )

# Convert relative path to an absolute path.
SCRIPTDIR=$( readlink -f $SCRIPTDIR )
CUSTOM=$( readlink -f $CUSTOM )
CONFIG_DIR=$( readlink -f $CONFIG_DIR )
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
  cp -a ${CONFIG_DIR}/resources/* squashfs-root/share/oem/

  # Rebuild the squashfs and cpio image.
  mksquashfs squashfs-root initrd-contents/usr.squashfs \
      -noappend -always-use-fragments

  pushd initrd-contents
    find . | cpio -o -H newc | gzip > "${CUSTOM}"
  popd

  # Cleanup
  rm -rf initrd-contents
  rm -rf squashfs-root
popd
