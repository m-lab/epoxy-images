#!/bin/sh
#
# This script gets uploaded and executed on the temporary VM that Packer
# creates when generating custom images. It should do everything necessary to
# prepare the custom image's environment for a platform control plane machine.

source /tmp/config.sh

apt install --yes docker.io

# Install etcdctl
curl --location https://github.com/etcd-io/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-linux-amd64.tar.gz | tar -xz
cp etcd-${ETCDCTL_VERSION}-linux-amd64/etcdctl /opt/bin
rm -rf etcd-${ETCDCTL_VERSION}-linux-amd64

# Create symlinks to persistent volume mount directories where various state
# will be stored. This should allow us to reinitialize the boot disk without
# disrupting the control plane cluster.
ln -s /mnt/cluster-data/kubelet /var/lib/kubelet
ln -s /mnt/cluster-data/kubernetes /etc/kubernetes

# Set the default KUBECONFIG location
echo -e "\nexport KUBECONFIG=/etc/kubernetes/admin.conf\n"

# Enable various systemd services.
systemctl enable docker
systemctl enable reboot-api-node.service
systemctl enable reboot-api-node.timer
systemctl enable token-server.service
systemctl enable bmc-store-password.service
systemctl enable mount-cluster-data.service
systemctl enable create-control-plane.service
