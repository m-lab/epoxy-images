#!/bin/bash
#
# customize_coreos_pxe_image.sh downloads the current stable coreos pxe images
# and generates a modified image that embeds custom scripts and static
# cloud-config.yml. These custom scripts conigure the static network IP and
# allow for running a post-boot setup script.

set -e
set -x
USAGE="USAGE: $0 <config dir> <epoxy-client> <vmlinuz-url> <initram-url> <custom-initram-name>"
CONFIG_DIR=${1:?Please specify path to configuration directory: $USAGE}
EPOXY_CLIENT=${2:?Please specify the path to the epoxy client binary: $USAGE}
VMLINUZ_URL=${3:?Please provide the URL for a coreos vmlinuz image: $USAGE}
INITRAM_URL=${4:?Please provide the URL for a coreos initram image: $USAGE}
CUSTOM=${5:?Please provide the name for a customized initram image: $USAGE}

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

  # Copy epoxy client to squashfs bin.
  install -D -m 755 ${EPOXY_CLIENT} squashfs-root/bin/

  # Install calico, cni, kubeadm, kubelet, and kubectl
  # TODO: calico

  # Container networking interface
  mkdir -p squashfs-root/cni/bin
  CNI_VERSION="v0.6.0"
  curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz" | tar -C squashfs-root/cni/bin -xz
  chmod 755 squashfs-root/cni/bin/*

  # kube* 
  # Commands adapted from:
  #   https://kubernetes.io/docs/setup/independent/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
  RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
  pushd squashfs-root/bin
    curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/"${RELEASE}"/bin/linux/amd64/{kubeadm,kubelet,kubectl}
    chmod 755 {kubeadm,kubelet,kubectl}
  popd

  # Startup configs
  mkdir -p squashfs-root/etc/systemd/system
  curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/kubelet.service" > squashfs-root/etc/systemd/system/kubelet.service
  mkdir -p squashfs-root/etc/systemd/system/kubelet.service.d
  curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/10-kubeadm.conf" > squashfs-root/etc/systemd/system/kubelet.service.d/10-kubeadm.conf

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
