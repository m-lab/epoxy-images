#!/bin/bash
#
# setup_stage3_mlxupdate.sh builds an initram filesystem based on the ubuntu
# xenial OS, that includes the Mellanox Firmware Tools and requisite kernel
# modules. With this image it is possible to flash a new ROM to a Mellanox NIC.
#
# Example:
#   ./setup_stage3_mlxupdate.sh /build config/stage3_mlxupdate

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
OUTPUT_KERNEL=${BUILD_DIR}/vmlinuz_${CONFIG_NAME}
OUTPUT_INITRAM=${BOOTSTRAP}.cpio.gz

##############################################################################
# Functions
##############################################################################

function unpack_url () {
  dir=$1
  url=$2
  tgz=$( basename $url )
  if ! test -d $dir ; then
    if ! test -f $tgz ; then
      wget $url
    fi
    tar -xvf $tgz
  fi
}


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
    debootstrap --arch amd64 xenial $BOOTSTRAP
    date --iso-8601=seconds --utc > $BOOTSTRAP/build.date
fi


# TODO: attempt to update mft version to one of the latest. The download is
# smaller and includes pre-built deb files. For example:
#     http://www.mellanox.com/downloads/MFT/mft-4.8.0-26-x86_64-deb.tgz
if ! test -d $BOOTSTRAP/root/mft-4.4.0-44 ; then
    pushd $BUILD_DIR
        unpack_url mft-4.4.0-44 http://www.mellanox.com/downloads/MFT/mft-4.4.0-44.tgz
        cp -ar mft-4.4.0-44 $BOOTSTRAP/root
    popd
fi

# Unmount the proc & sys dirs if we encounter a problem within the following
# block.
trap "umount_proc_and_sys $BOOTSTRAP" EXIT

# Install extra packages and
mount_proc_and_sys $BOOTSTRAP

    # Extra packages needed for correct operation.
    PACKAGES=`cat ${CONFIG_DIR}/extra.packages ${CONFIG_DIR}/build.packages`

    # Add extra apt sources to install latest kernel image and headers.
    # TODO: only append the source once.
    LINE='deb http://archive.ubuntu.com/ubuntu/ xenial-updates universe main multiuniverse'
    if ! grep -q "$LINE" $BOOTSTRAP/etc/apt/sources.list ; then
        chroot $BOOTSTRAP bash -c "echo '$LINE' >> /etc/apt/sources.list"
    fi
    chroot $BOOTSTRAP apt-get update --fix-missing
    DEBIAN_FRONTEND=noninteractive chroot $BOOTSTRAP apt-get install -y $PACKAGES

    # Figure out the newest installed linux kernel version.
    # TODO: is there a better way?
    pushd $BOOTSTRAP/boot
        KERNEL_VERSION=`ls vmlinuz-*`
        KERNEL_VERSION=${KERNEL_VERSION##vmlinuz-}
    popd

    # Update install.sh to use installed (not the running) kernel version.
    sed -i -e 's/g_kernel_version=.*/g_kernel_version="'$KERNEL_VERSION'"/g' \
        $BOOTSTRAP/root/mft-4.4.0-44/install.sh

    # Run the mlx firmware tools installation script.
    chroot $BOOTSTRAP bash -c "cd /root/mft-4.4.0-44 && ./install.sh"

    # dynamic kernel module support (dkms) builds for the currently running
    # kernel, so explicitly build for the kernel installed in the bootstrapfs.
    chroot $BOOTSTRAP dkms install kernel-mft-dkms/4.4.0 -k $KERNEL_VERSION

    echo "Removing unnecessary packages and files from $BOOTSTRAP"
    # Remove mft directory since the unnecessary binary packages are large.
    chroot $BOOTSTRAP rm -rf /root/mft-4.4.0-44

    # NOTE: DO NOT "autoremove" gcc or make, as this uninstalls dkms and the
    # mft module built and installed above.
    #
    # Remove unnecessary packages to save space.
    for i in 1 2 ; do
    # TODO: order seems to matter, so run twice to get everything.
    chroot $BOOTSTRAP apt-get autoremove -y \
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
    done

    chroot $BOOTSTRAP apt-get clean -y

    # Copy kernel image to output directory before removing it.
    cp $BOOTSTRAP/boot/vmlinuz-${KERNEL_VERSION} ${OUTPUT_KERNEL}

    # Backup the kernel modules with the dkms module.
    cp -ar $BOOTSTRAP/lib/modules/${KERNEL_VERSION} \
        $BOOTSTRAP/lib/modules/${KERNEL_VERSION}.orig

    # Frees about 50MB
    chroot $BOOTSTRAP apt-get autoremove -y make gcc
    chroot $BOOTSTRAP apt-get autoclean

    # Restore the kernel modules.
    rm -rf $BOOTSTRAP/lib/modules/${KERNEL_VERSION}
    mv $BOOTSTRAP/lib/modules/${KERNEL_VERSION}.orig \
        $BOOTSTRAP/lib/modules/${KERNEL_VERSION}

umount_proc_and_sys $BOOTSTRAP
trap '' EXIT


################################################################################
# Init
################################################################################
# Kernel panics unless /init is defined. Use systemd for init.
ln --force --symbolic sbin/init $BOOTSTRAP/init
cp $CONFIG_DIR/fstab $BOOTSTRAP/etc/fstab

# Enable simple rc.local script for post-setup processing.
# rc.local.service runs after networking.service
cp $CONFIG_DIR/rc.local $BOOTSTRAP/etc/rc.local
chroot $BOOTSTRAP systemctl enable rc.local.service

################################################################################
# Network
################################################################################
# Enable static resolv.conf
# TODO: use systemd for network configuration entirely.
rm -f $BOOTSTRAP/etc/resolv.conf
cp $CONFIG_DIR/resolv.conf $BOOTSTRAP/etc/resolv.conf
# If permissions are incorrect, apt-get will fail to read contents.
chmod 644 $BOOTSTRAP/etc/resolv.conf

# Set a default root passwd.
# TODO: only allow login via ssh?
chroot $BOOTSTRAP bash -c 'echo -e "demo\ndemo\n" | passwd'

################################################################################
# SSH
################################################################################
# Disable root login via ssh.
if ! grep -q -E '^PermitRootLogin .*' $BOOTSTRAP/etc/ssh/sshd_config ; then
    sed -i -e 's/^PermitRootLogin .*/PermitRootLogin prohibit-password/g' \
        $BOOTSTRAP/etc/ssh/sshd_config
fi

# Enable sshd.
chroot $BOOTSTRAP systemctl enable ssh.service

# TODO: get ssh keys from some external source.
# TODO: investigate ssh-import-id as an alternative here, or a copy from GCS.
# echo "Adding SSH authorized keys"
# mkdir -p $BOOTSTRAP/root/.ssh
# cp $CONFIG_DIR/authorized_keys  $BOOTSTRAP/root/.ssh/authorized_keys
# chown root:root $BOOTSTRAP/root/.ssh/authorized_keys
# chmod 700 $BOOTSTRAP/root/


mkdir -p $BOOTSTRAP/usr/local/util
cp $CONFIG_DIR/flashrom.sh $BOOTSTRAP/usr/local/util
cp $CONFIG_DIR/updaterom.sh $BOOTSTRAP/usr/local/util
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
