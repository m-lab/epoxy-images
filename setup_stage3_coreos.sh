#!/bin/bash
#
# This script downloads the current stable coreos pxe images and generates a
# modified image that embeds custom scripts, all the binaries required to run
# kubernetes services, and static cloud-config.yml. These custom scripts
# conigure the static network IP and allow for running a post-boot setup script.

set -euxo pipefail

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

  # Install multus, index2ip, other cni binaries, kubeadm, kubelet, and kubectl.

  # Install the cni binaries: bridge, flannel, host-local, ipvlan, loopback, and
  # others.
  mkdir -p squashfs-root/cni/bin
  CNI_VERSION="v0.7.1"
  curl --location "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz" | tar --directory=squashfs-root/cni/bin -xz

  # Install multus and index2ip.
  TMPDIR=$(mktemp -d)
  pushd ${TMPDIR}
    mkdir -p src/github.com/intel
	pushd src/github.com/intel
	   git clone https://github.com/intel/multus-cni.git
	   pushd multus-cni
	     git checkout v3.1
	   popd
	popd
  popd
  # TODO: restore `-u` flag. Removed so `go get` works on detached head.
  GOPATH=${TMPDIR} CGO_ENABLED=0 go get -ldflags '-w -s' github.com/intel/multus-cni/multus
  GOPATH=${TMPDIR} CGO_ENABLED=0 go get -u -ldflags '-w -s' github.com/m-lab/index2ip
  cp ${TMPDIR}/bin/multus squashfs-root/cni/bin
  cp ${TMPDIR}/bin/index2ip squashfs-root/cni/bin
  chmod 755 squashfs-root/cni/bin/*
  rm -Rf ${TMPDIR}

  # Install crictl.
  mkdir -p squashfs-root/bin
  CRI_VERSION="v1.12.0"
  wget https://github.com/kubernetes-incubator/cri-tools/releases/download/${CRI_VERSION}/crictl-${CRI_VERSION}-linux-amd64.tar.gz
  tar zxvf crictl-${CRI_VERSION}-linux-amd64.tar.gz -C squashfs-root/bin/
  rm -f crictl-${CRI_VERSION}-linux-amd64.tar.gz

  # Install the kube* commands.
  # Installation commands adapted from:
  #   https://kubernetes.io/docs/setup/independent/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
  K8S_RELEASE="$(echo v1.12.3 | tee squashfs-root/share/oem/installed_k8s_version.txt)"
  pushd squashfs-root/bin
    curl --location --remote-name-all https://storage.googleapis.com/kubernetes-release/release/"${K8S_RELEASE}"/bin/linux/amd64/{kubeadm,kubelet,kubectl}
    chmod 755 {kubeadm,kubelet,kubectl}
  popd

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
