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

  # Copy resources to the "/usr/share/oem" directory.
  mkdir -p fake-usr/share/oem
  cp -ar ${SCRIPTDIR}/resources/* fake-usr/share/oem/

  # Append the files to the squashfs and re-cpio image.
  mksquashfs fake-usr initrd-contents/usr.squashfs -always-use-fragments
  pushd initrd-contents
    find . | cpio -o -H newc | gzip > "${CUSTOM}"
  popd

  # Cleanup
  rm -rf initrd-contents
  rm -rf fake-usr
popd
