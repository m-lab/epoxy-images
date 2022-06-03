#!/bin/bash
#
# setup_stage3_ubuntu.sh builds an initram image based on the Ubuntu Focal
# (20.04) OS with all package upgraded to their latest versions, that includes
# M-Lab configs and scripts, epoxy_client and k8s-related binaries
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
OUTPUT_KERNEL="${BUILD_DIR}/stage3_kernel_ubuntu.vmlinuz"
OUTPUT_INITRAM="${BUILD_DIR}/stage3_initramfs_ubuntu.cpio.gz"

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

# Make sure that the k8s version configured in K8S_VERSION in this repository
# is not greater than the version currently running in the API cluster.
CLUSTER_VERSION=$(
  curl --insecure --silent \
    https://api-platform-cluster.$PROJECT.measurementlab.net:6443/version \
    | jq -r '.gitVersion'
)
LOWEST_VERSION=$(
  echo -e "${CLUSTER_VERSION}\n${K8S_VERSION}" | sort --version-sort | head --lines 1
)
if [[ $LOWEST_VERSION != $K8S_VERSION ]]; then
  echo "K8S_VERSION is ${K8S_VERSION}), which is greater than the cluster version of ${CLUSTER_VERSION}. Exiting..."
  exit 1
fi

# Note: this step cannot be performed by docker build because it requires
# --privileged mode to mount /proc.
if ! test -f $BOOTSTRAP/build.date ; then
    mkdir -p $BOOTSTRAP
    rm -rf $BOOTSTRAP/dev
    # Disable interactive prompt from grub-pc or other packages.
    export DEBIAN_FRONTEND=noninteractive

    # A comma-separated list of additional packages we want installed.
    PACKAGES="busybox,ca-certificates,conntrack,curl,dbus,dmsetup,docker.io,ethtool,"
    PACKAGES+="iproute2,jq,kexec-tools,less,linux-base,linux-generic,net-tools,"
    PACKAGES+="openssh-server,parted,pciutils,socat,sudo,systemd-sysv,udev,"
    PACKAGES+="unattended-upgrades,usbutils,vim,wget,xfsprogs"

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
    # Update the apt repositories.
    chroot $BOOTSTRAP apt-get update --fix-missing

    # Upgrade all installed packages.
    chroot $BOOTSTRAP apt-get dist-upgrade --yes

    # Install ipmitool to configure DRAC during stage1.
    chroot $BOOTSTRAP apt-get install --yes ipmitool

    # Remove unnecessary packages to save space.
    chroot $BOOTSTRAP apt-get remove --yes \
        linux-headers-generic \
        linux-generic \
        ^linux-headers \
        linux-firmware

    chroot $BOOTSTRAP apt-get autoremove --yes
    chroot $BOOTSTRAP apt-get clean --yes

    # Copy the most recent kernel image to output directory before removing it.
    pushd $BOOTSTRAP/boot
        cp $(ls -v vmlinuz-* | tail -n1) ${OUTPUT_KERNEL}
    popd

    # Frees about 50MB
    chroot $BOOTSTRAP apt-get autoclean

    # Free up a little more space.
    rm -f $BOOTSTRAP/boot/vmlinuz*
    rm -f $BOOTSTRAP/boot/initrd*

umount_proc_and_sys $BOOTSTRAP
trap '' EXIT


################################################################################
# System / Users / M-Lab
################################################################################
# Copy in all custom M-Lab files.
cp --recursive --preserve=mode $CONFIG_DIR/* $BOOTSTRAP/

# Kernel panics unless /init is defined. Use systemd for init.
ln --force --symbolic sbin/init $BOOTSTRAP/init

# Add mlab user, setup .ssh directory.
if ! chroot $BOOTSTRAP bash -c 'id -u mlab'; then
  chroot $BOOTSTRAP bash -c 'adduser --disabled-password --gecos "" mlab'
  chroot $BOOTSTRAP bash -c 'chown -R mlab:mlab /home/mlab'
fi

# Add reboot-api user, setup .ssh directory.
if ! chroot $BOOTSTRAP bash -c 'id -u reboot-api'; then
  chroot $BOOTSTRAP bash -c 'adduser --system --disabled-password --gecos "" reboot-api'
  chroot $BOOTSTRAP bash -c 'chown -R reboot-api:nogroup /home/reboot-api'
fi

# Add /opt/bin to root's PATH
echo -e "\nexport PATH=$PATH:/opt/bin" >> $BOOTSTRAP/root/.bashrc

# For root, let crictl know where to find the CRI socket.
echo -e "\nexport CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock" \
  >> $BOOTSTRAP/root/.bashrc

################################################################################
# Systemd
################################################################################
# Don't go beyond multi-user.target as these are headless systems.
chroot $BOOTSTRAP bash -c 'systemctl set-default multi-user.target'

for unit in $(find $CONFIG_DIR/etc/systemd/system -maxdepth 1 -type f -printf "%f\n"); do
  chroot $BOOTSTRAP bash -c "systemctl enable $unit"
done

# Install the kubelet.service unit file.
curl --silent --show-error --location \
    "https://raw.githubusercontent.com/kubernetes/release/v0.7.0/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service" \
    > $BOOTSTRAP/etc/systemd/system/kubelet.service

# Install kubelet.service config overrides.
mkdir --parents $BOOTSTRAP/etc/systemd/system/kubelet.service.d
curl --silent --show-error --location \
    "https://raw.githubusercontent.com/kubernetes/release/v0.7.0/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf" \
     > $BOOTSTRAP/etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Enable various services.
chroot $BOOTSTRAP systemctl enable ssh.service
chroot $BOOTSTRAP systemctl enable systemd-networkd.service

# Disable various services
chroot $BOOTSTRAP systemctl disable docker.service
chroot $BOOTSTRAP systemctl disable docker.socket
# Not only do we disable docker.service and docker.socket, but we also mask it
# to be 100% sure it doesn't get started through any sort of dependency. The
# reason we absolutely don't want Docker running is that kubeadm tries to
# autodetect which CRI is in use by looking for common socket paths. If it
# finds a Docker socket it will use that. In our case, we want it to find the
# containerd socket and auto configure the kubelet to use that socket for the
# CRI.
chroot $BOOTSTRAP systemctl mask docker.service
chroot $BOOTSTRAP systemctl disable ondemand.service

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

# Sign all of the host ssh public keys using the SSH CA private key. This key is
# stored in GCP Secret Manager which is made available to this script via an
# environment variable. See cloudbuild.yaml in the root of this repo for details.
pushd $BOOTSTRAP/etc/ssh
# Don't log this command, since it contains sensitive private key material.
set +x
echo $SSH_HOST_CA_KEY > ./host_ca
chmod 0600 ./host_ca
set -x
for f in $(ls ssh_host_*_key.pub); do
  ssh-keygen -s host_ca -I mlab -h -V always:forever $f
  echo "HostCertificate /etc/ssh/$f" >> /etc/ssh/sshd_config
done
rm ./host_ca
popd

################################################################################
# Kubernetes / CNI / crictl
################################################################################
# Install the CNI binaries.
mkdir -p ${BOOTSTRAP}/opt/cni/bin
curl --location "https://github.com/containernetworking/plugins/releases/download/${K8S_CNI_VERSION}/cni-plugins-linux-amd64-${K8S_CNI_VERSION}.tgz" \
  | tar --directory=${BOOTSTRAP}/opt/cni/bin -xz

# Install multus, index2ip, netctl and flannel.
TMPDIR=$(mktemp -d)
pushd ${TMPDIR}
curl --location "https://github.com/k8snetworkplumbingwg/multus-cni/releases/download/v${MULTUS_CNI_VERSION}/multus-cni_${MULTUS_CNI_VERSION}_linux_amd64.tar.gz" \
  | tar -xz
curl --location "https://github.com/flannel-io/cni-plugin/releases/download/${K8S_FLANNELCNI_VERSION}/flannel-amd64" \
  > flannel
GOPATH=${TMPDIR} CGO_ENABLED=0 go get -u -ldflags '-w -s' github.com/m-lab/index2ip@v1.2.0
GOPATH=${TMPDIR} CGO_ENABLED=0 go get -u -ldflags '-w -s' github.com/m-lab/cni-plugins/netctl@v1.0.0
cp ${TMPDIR}/multus-cni_${MULTUS_CNI_VERSION}_linux_amd64/multus-cni ${BOOTSTRAP}/opt/cni/bin/multus
cp ${TMPDIR}/bin/index2ip ${BOOTSTRAP}/opt/cni/bin
cp ${TMPDIR}/bin/netctl ${BOOTSTRAP}/opt/cni/bin
cp ${TMPDIR}/flannel ${BOOTSTRAP}/opt/cni/bin
chmod 755 ${BOOTSTRAP}/opt/cni/bin/*
rm -Rf ${TMPDIR}

# Make all the shims so that network plugins can be debugged.
pushd ${BOOTSTRAP}/opt/shimcni/bin
for i in ${BOOTSTRAP}/opt/cni/bin/*; do
    # NOTE: the target path does not exist at this moment, but that's the file
    # the symlink should reference in the final image filesystem.
    ln --symbolic --force /opt/shimcni/bin/shim.sh $(basename "$i")
done

# Install crictl.
mkdir -p ${BOOTSTRAP}/opt/bin
wget https://github.com/kubernetes-incubator/cri-tools/releases/download/${K8S_CRICTL_VERSION}/crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz
tar zxvf crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz -C ${BOOTSTRAP}/opt/bin/
rm -f crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz

# Install the kube* commands.
# Installation commands adapted from:
#   https://kubernetes.io/docs/setup/independent/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
pushd ${BOOTSTRAP}/opt/bin
curl --location --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
chmod 755 {kubeadm,kubelet,kubectl}
popd

# The default kubelet.service.d/10-kubeadm.conf looks for kubelet at /usr/bin.
ln --symbolic --force /opt/bin/kubelet $BOOTSTRAP/usr/bin/kubelet

################################################################################
# Add epoxy client to initramfs
################################################################################
install -D -m 755 ${EPOXY_CLIENT} ${BOOTSTRAP}/usr/bin/epoxy_client

# Build the initramfs from the bootstrap filesystem.
pushd ${BOOTSTRAP}
    find . | cpio -H newc -o | gzip -c > ${OUTPUT_INITRAM}
popd
# Copy file to output with all read permissions.
install -D -m 0644 ${OUTPUT_KERNEL} ${OUTPUT_INITRAM} ${OUTPUT_DIR}

echo "Success: ${OUTPUT_KERNEL}"
echo "Success: ${OUTPUT_INITRAM}"
