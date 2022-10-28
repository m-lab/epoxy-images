#!/bin/bash
#
# setup_stage1_minimal.sh builds an initram image based on the Ubuntu Focal
# (20.04) OS, that includes epoxy_client and configuration suitable for a
# stage1 boot. With this image it ispossible to create UEFI or BIOS boot media
# for USB or CD.
# Example:
#   ./setup_stage1_minimal.sh /build /workspace/output configs/stage1_minimal \
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
BOOTSTRAP=${BUILD_DIR}/initramfs_${CONFIG_NAME}
OUTPUT_KERNEL=${BUILD_DIR}/stage1_kernel.vmlinuz
OUTPUT_INITRAM=${BUILD_DIR}/stage1_initramfs.cpio.gz

##############################################################################
# Functions
##############################################################################

function mount_proc_and_sys() {
    local bootstrap=$1
    mount -t proc proc $bootstrap/proc
    mount -t sysfs sysfs $bootstrap/sys
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
       --components=main,universe,multiverse --arch amd64 jammy $BOOTSTRAP

    # Mark the build complete.
    date --iso-8601=seconds --utc > $BOOTSTRAP/build.date
fi

# Unmount the proc & sys dirs if we encounter a problem below.
trap "umount_proc_and_sys $BOOTSTRAP" EXIT

mount_proc_and_sys $BOOTSTRAP
    # Add extra apt sources to install latest kernel image and headers.
    LINE='deb http://archive.ubuntu.com/ubuntu/ jammy-updates main universe multiverse'
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
        linux-firmware \
        python3 \
        grub-pc \
        grub-common \
        grub2-common \
        grub-gfxpayload-lists \
        grub-pc-bin

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
# Kernel panics if /init is undefined. Use systemd for init.
ln --force --symbolic sbin/init $BOOTSTRAP/init
install -D --mode 644 $CONFIG_DIR/fstab $BOOTSTRAP/etc/fstab

# Don't go beyond multi-user.target as these are headless systems.
chroot $BOOTSTRAP bash -c 'systemctl set-default multi-user.target'

# Enable simple rc.local script for post-setup processing.
# NOTE: rc.local.service runs after networking.service
# NOTE: This script does not need to be explicitly enabled. There is a default
# systemd compatibility unit rc-local.service that automatically gets enabled
# if /etc/rc.local exists and is executable.
install -D --mode 755 $CONFIG_DIR/rc.local $BOOTSTRAP/etc/rc.local

# For enabling various kernel modules.
cp $CONFIG_DIR/modules $BOOTSTRAP/etc/modules

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
# Add epoxy client to initramfs
################################################################################
install -D -m 755 $EPOXY_CLIENT $BOOTSTRAP/usr/bin/epoxy_client

# Build the initramfs from the bootstrap filesystem.
pushd $BOOTSTRAP
    find . | cpio -H newc -o | gzip -c > ${OUTPUT_INITRAM}
popd
# Copy file to output with all read permissions.
install -m 0644 ${OUTPUT_KERNEL} ${OUTPUT_INITRAM} ${OUTPUT_DIR}

echo "Success: ${OUTPUT_KERNEL}"
echo "Success: ${OUTPUT_INITRAM}"
