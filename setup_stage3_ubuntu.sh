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
OUTPUT_KERNEL="${BUILD_DIR}/${CONFIG_NAME}.vmlinuz"
OUTPUT_INITRAM="${BOOTSTRAP}.cpio.gz"

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
      cat ${CONFIG_DIR}/extra.packages | xargs echo | tr ' ' ','
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
    #NPKrm -f $BOOTSTRAP/boot/vmlinuz*
    #NPKrm -f $BOOTSTRAP/boot/initrd*

umount_proc_and_sys $BOOTSTRAP
trap '' EXIT


################################################################################
# Init
################################################################################
# Kernel panics if /init is undefined. Use systemd for init.
ln --force --symbolic sbin/init $BOOTSTRAP/init
install -D --mode 644 $CONFIG_DIR/fstab $BOOTSTRAP/etc/fstab

# Install simple rc.local script for post-setup processing.
# NOTE: rc.local.service runs after networking.service
# NOTE: This script does not need to be explicitly enabled. There is a default
# systemd compatibility unit rc-local.service that automatically gets enabled
# if /etc/rc.local exists and is executable.
install -D --mode 755 $CONFIG_DIR/rc.local $BOOTSTRAP/etc/rc.local

################################################################################
# Network
################################################################################

# TODO: use systemd for network configuration entirely.
rm -f $BOOTSTRAP/etc/resolv.conf
install -D --mode 644 $CONFIG_DIR/resolv.conf $BOOTSTRAP/etc/resolv.conf

# Set a default root passwd.
# TODO: disable root login except by ssh?
chroot $BOOTSTRAP bash -c 'echo -e "demo\ndemo\n" | passwd'

################################################################################
# SSH
################################################################################
# Disable root login with password via ssh.
if ! grep -q -E '^PermitRootLogin prohibit-password' $BOOTSTRAP/etc/ssh/sshd_config ; then
    sed -i -e 's/.*PermitRootLogin .*/PermitRootLogin prohibit-password/g' \
        $BOOTSTRAP/etc/ssh/sshd_config
fi

# Enable sshd.
chroot $BOOTSTRAP systemctl enable ssh.service

# Copy the authorized_keys file.
# TODO: Get ssh keys from some external source.
# TODO: investigate ssh-import-id as an alternative here, or a copy from GCS.
install -D --mode 644 $CONFIG_DIR/authorized_keys $BOOTSTRAP/root/.ssh/authorized_keys

################################################################################
# M-Lab resources
################################################################################
# Make sure /usr/share/oem exists
mkdir -p $BOOTSTRAP/usr/share/oem

# Copy resources to the "/usr/share/oem" directory.
cp -a ${CONFIG_DIR}/resources/* $BOOTSTRAP/usr/share/oem

################################################################################
# Kubernetes
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
cp -a ${CONFIG_DIR}/shim.sh .
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
echo ${K8S_VERSION} > ${BOOTSTRAP}/usr/share/oem/installed_k8s_version.txt
pushd ${BOOTSTRAP}/opt/bin
curl --location --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
chmod 755 {kubeadm,kubelet,kubectl}
popd

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