#!/bin/bash
#
# setup_stage3_ubuntu.sh builds an initram image based on the Ubuntu Focal
# (20.04) OS, that includes M-Lab configs and scripts, epoxy_client and k8s-related binaries
#
# Example:
#   ./setup_stage3_ubuntu.sh /build /workspace/output configs/stage3_ubuntu \
#       output/epoxy_client

set -x
set -e
set -u

BUILD_DIR=${1:?Name of build directory}
BUILD_DIR=$( realpath $BUILD_DIR )

OUTPUT_DIR=${2:?Name of directory to copy output files}
OUTPUT_DIR=$( realpath $OUTPUT_DIR )

CONFIG_DIR=${3:?Name of directory containing configuration files}
CONFIG_DIR=$( realpath $CONFIG_DIR )

EPOXY_CLIENT=${4:?Name of epoxy client binary to include in output initram}
EPOXY_CLIENT=$( realpath $EPOXY_CLIENT )

CONFIG_NAME=$( basename $CONFIG_DIR )
BOOTSTRAP="${BUILD_DIR}/initramfs_${CONFIG_NAME}"
OUTPUT_KERNEL="${BUILD_DIR}/stage3_kernel.vmlinuz"
OUTPUT_INITRAM="${BUILD_DIR}/stage3_initramfs.cpio.gz"

##############################################################################
# Functions
##############################################################################

function mount_proc_and_sys() {
    local bootstrap=$1
    mount -t proc none $bootstrap/proc
    mount -t sysfs none $bootstrap/sys
}


function umount_proc_and_sys() {
    local bootstrap=$1
    umount $bootstrap/proc
    umount $bootstrap/sys
}

##############################################################################
# Main script
##############################################################################

# Note: this step cannot be performed by docker build because it requires
# --privileged mode to mount /proc.
if ! test -f $BOOTSTRAP/build.date ; then
    mkdir -p $BOOTSTRAP
    rm -rf $BOOTSTRAP/dev
    # Disable interactive prompt from grub-pc or other packages.
    export DEBIAN_FRONTEND=noninteractive

    # Create comma-separated list.
    PACKAGES=$(
      cat ${CONFIG_DIR}/build/extra.packages | xargs echo | tr ' ' ','
    )

    # Create 'minbase' bootstrap fs.
    debootstrap --variant=minbase --include "${PACKAGES}" \
      --components=main,universe,multiverse --arch amd64 focal $BOOTSTRAP

    # Mark the build complete.
    date --iso-8601=seconds --utc > $BOOTSTRAP/build.date
fi

# Unmount the proc & sys dirs if we encounter a problem below.
trap "umount_proc_and_sys $BOOTSTRAP" EXIT

mount_proc_and_sys $BOOTSTRAP
    # Add extra apt sources to install latest kernel image and headers.
    LINE='deb http://archive.ubuntu.com/ubuntu/ focal-updates main universe multiverse'
    if ! grep -q "$LINE" $BOOTSTRAP/etc/apt/sources.list ; then
        chroot $BOOTSTRAP bash -c "echo '$LINE' >> /etc/apt/sources.list"
    fi
    chroot $BOOTSTRAP apt-get update --fix-missing

    # Figure out the newest installed linux kernel version.
    # TODO: is there a better way?
    pushd $BOOTSTRAP/boot
        KERNEL_VERSION=`ls vmlinuz-*`
        KERNEL_VERSION=${KERNEL_VERSION##vmlinuz-}
    popd

    # Install ipmitool to configure DRAC during stage1.
    chroot $BOOTSTRAP apt-get install -y ipmitool

    # Remove unnecessary packages to save space.
    chroot $BOOTSTRAP apt-get remove -y \
        linux-headers-generic \
        linux-generic \
        linux-headers-${KERNEL_VERSION} \
        linux-headers-${KERNEL_VERSION%%-generic} \
        linux-firmware

    chroot $BOOTSTRAP apt-get autoremove -y
    chroot $BOOTSTRAP apt-get clean -y

    # Copy kernel image to output directory before removing it.
    cp $BOOTSTRAP/boot/vmlinuz-${KERNEL_VERSION} ${OUTPUT_KERNEL}

    # Frees about 50MB
    chroot $BOOTSTRAP apt-get autoclean

    # Free up a little more space.
    rm -f $BOOTSTRAP/boot/vmlinuz*
    rm -f $BOOTSTRAP/boot/initrd*

umount_proc_and_sys $BOOTSTRAP
trap '' EXIT


################################################################################
# Init
################################################################################
# Install simple rc.local script for post-setup processing.
# NOTE: rc-local.service runs after networking.service
# NOTE: This script does not need to be explicitly enabled. There is a default
# systemd compatibility unit rc-local.service that automatically gets enabled
# if /etc/rc.local exists and is executable.
install -D --mode 755 $CONFIG_DIR/etc/rc.local $BOOTSTRAP/etc/rc.local

# Add mlab user, setup .ssh directory.
chroot $BOOTSTRAP bash -c 'adduser --disabled-password --gecos "" mlab'
chroot $BOOTSTRAP bash -c 'mkdir --mode 0755 --parents /home/mlab/.ssh'

################################################################################
# Systemd
################################################################################
# Don't go beyond multi-user.target as these are headless systems.
chroot $BOOTSTRAP bash -c 'systemctl set-default multi-user.target'

cp -a $CONFIG_DIR/systemd/* $BOOTSTRAP/etc/systemd/system/
for unit in $(find $CONFIG_DIR/systemd/ -maxdepth 1 -type f -printf "%f\n"); do
  chroot $BOOTSTRAP bash -c "systemctl enable $unit"
done

# Install the kubelet.service unit file.
curl --silent --show-error --location \
    "https://raw.githubusercontent.com/kubernetes/kubernetes/${K8S_VERSION}/build/debs/kubelet.service"
    > $BOOSTRAP/etc/systemd/system/kubelet.service

# Install kubelet.service config overrides.
mkdir --parents $BOOTSTRAP/etc/systemd/system/kubelet.service.d
curl --silent --show-error --location \
    "https://raw.githubusercontent.com/kubernetes/kubernetes/${K8S_VERSION}/build/debs/10-kubeadm.conf" \
     > $BOOTSTRAP/etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Enable various services.
chroot $BOOTSTRAP systemctl enable docker.service
chroot $BOOTSTRAP systemctl enable kubelet.service
chroot $BOOTSTRAP systemctl enable ssh.service

################################################################################
# Network
################################################################################
# TODO: use systemd for network configuration entirely.
rm -f $BOOTSTRAP/etc/resolv.conf
install -D --mode 644 $CONFIG_DIR/etc/resolv.conf $BOOTSTRAP/etc/resolv.conf

# Set a default root passwd.
# TODO: disable root login except by ssh?
chroot $BOOTSTRAP bash -c 'echo -e "demo\ndemo\n" | passwd'

################################################################################
# SSH
################################################################################
# Disable root login via ssh.
if ! grep -q -E '^PermitRootLogin no' $BOOTSTRAP/etc/ssh/sshd_config ; then
    sed -i -e 's/.*PermitRootLogin .*/PermitRootLogin no/g' \
        $BOOTSTRAP/etc/ssh/sshd_config
fi

# Disable password login via ssh.
if ! grep -q -E '^PasswordAuthentication no' $BOOTSTRAP/etc/ssh/sshd_config ; then
    sed -i -e 's/.*PasswordAuthentication .*/PasswordAuthentication no/g' \
        $BOOTSTRAP/etc/ssh/sshd_config
fi

# Copy the authorized_keys file.
# TODO: Get ssh keys from some external source.
# TODO: investigate ssh-import-id as an alternative here, or a copy from GCS.
install -D --mode 644 $CONFIG_DIR/user/authorized_keys $BOOTSTRAP/home/mlab/.ssh/authorized_keys

################################################################################
# M-Lab resources
################################################################################
# Make sure /opt/mlab/bin exists
mkdir -p $BOOTSTRAP/opt/mlab/bin
# Copy binaries and scripts to the "/opt/mlab/bin" directory.
cp -a ${CONFIG_DIR}/bin/* $BOOTSTRAP/opt/mlab/bin/

# Link fix-hung-shim.sh to /etec/periodic/15min directory.
mkdir -p $BOOTSTRAP/etc/periodic/15min
ln -s /opt/mlab/bin/fix-hung-shim.sh $BOOTSTRAP/etc/periodic/15min/fix-hung-shim.sh

# Load any necessary modules at boot.
cp -a $CONFIG_DIR/etc/modules $BOOTSTRAP/etc/modules

# Allow the mlab user to use sudo to do anything, without a password
install -D --mode 440 $CONFIG_DIR/etc/sudoers_mlab.conf $BOOTSTRAP/etc/sudoers.d/mlab

################################################################################
# Kubernetes / Docker
################################################################################
# Install the CNI binaries: bridge, flannel, host-local, ipvlan, loopback, etc.
mkdir -p ${BOOTSTRAP}/opt/cni/bin
curl --location "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" \
  | tar --directory=${BOOTSTRAP}/opt/cni/bin -xz

# Make all the shims so that network plugins can be debugged.
mkdir -p ${BOOTSTRAP}/opt/shimcni/bin
pushd ${BOOTSTRAP}/opt/shimcni/bin
for i in ${BOOTSTRAP}/opt/cni/bin/*; do
    # NOTE: the target path does not exist at this moment, but that's the file
    # the symlink should reference in the final image filesystem.
    ln -s /opt/shimcni/bin/shim.sh $(basename "$i")
done
cp -a ${CONFIG_DIR}/bin/shim.sh .
chmod +x shim.sh
popd

# Install multus and index2ip.
TMPDIR=$(mktemp -d)
pushd ${TMPDIR}
mkdir -p src/github.com/intel
pushd src/github.com/intel
    git clone https://github.com/intel/multus-cni.git
    pushd multus-cni
        git checkout v3.2
    popd
  popd
popd
# TODO: restore `-u` flag. Removed so `go get` works on detached head.
GOPATH=${TMPDIR} CGO_ENABLED=0 go get -ldflags '-w -s' github.com/intel/multus-cni/multus
GOPATH=${TMPDIR} CGO_ENABLED=0 go get -u -ldflags '-w -s' github.com/m-lab/index2ip
cp ${TMPDIR}/bin/multus ${BOOTSTRAP}/opt/cni/bin
cp ${TMPDIR}/bin/index2ip ${BOOTSTRAP}/opt/cni/bin
chmod 755 ${BOOTSTRAP}/opt/cni/bin/*
rm -Rf ${TMPDIR}

# Install crictl.
mkdir -p ${BOOTSTRAP}/opt/bin
wget https://github.com/kubernetes-incubator/cri-tools/releases/download/${CRI_VERSION}/crictl-${CRI_VERSION}-linux-amd64.tar.gz
tar zxvf crictl-${CRI_VERSION}-linux-amd64.tar.gz -C ${BOOTSTRAP}/opt/bin/
rm -f crictl-${CRI_VERSION}-linux-amd64.tar.gz

# Install the kube* commands.
# Installation commands adapted from:
#   https://kubernetes.io/docs/setup/independent/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
pushd ${BOOTSTRAP}/opt/bin
curl --location --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
chmod 755 {kubeadm,kubelet,kubectl}
popd


# The default kubelet.service.d/10-kubeadm.conf looks for kubelet at /usr/bin.
ln --symbolic --force /opt/bin/kubelet /usr/bin/kubelet

# Adds a configuration file for the Docker daemon.
install -D --mode 644 $CONFIG_DIR/etc/docker-daemon.json $BOOTSTRAP/etc/docker/daemon.json

################################################################################
# Add epoxy client to initramfs
################################################################################
install -D -m 755 ${EPOXY_CLIENT} ${BOOTSTRAP}/usr/bin/epoxy_client

# Build the initramfs from the bootstrap filesystem.
pushd ${BOOTSTRAP}
    find . | cpio -H newc -o | gzip -c > ${OUTPUT_INITRAM}
popd
# Copy file to output with all read permissions.
install -m 0644 ${OUTPUT_KERNEL} ${OUTPUT_INITRAM} ${OUTPUT_DIR}

echo "Success: ${OUTPUT_KERNEL}"
echo "Success: ${OUTPUT_INITRAM}"
