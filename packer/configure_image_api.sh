#!/bin/sh
#
# This script gets uploaded and executed on the temporary VM that Packer
# creates when generating custom images. It should do everything necessary to
# prepare the custom image's environment for a platform control plane machine.

source /tmp/config.sh

apt install --yes \
  docker.io \
  jsonnet

# Install etcdctl
curl --location https://github.com/etcd-io/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-linux-amd64.tar.gz | tar -xz
cp etcd-${ETCDCTL_VERSION}-linux-amd64/etcdctl /opt/bin
rm -rf etcd-${ETCDCTL_VERSION}-linux-amd64

# Create symlinks to persistent volume mount directories where various state
# will be stored. This should allow us to reinitialize the boot disk without
# disrupting the control plane cluster.
ln -s /mnt/cluster-data/kubelet /var/lib/kubelet
ln -s /mnt/cluster-data/kubernetes /etc/kubernetes

# Set various etcdctl configurations
cat <<- EOF | tee -a /root/.profile /root/.bashrc

	export ETCDCTL_API=3
	export ETCDCTL_DIAL_TIMEOUT=3s
	export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
	export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/peer.crt
	export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/peer.key
	export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
	export KUBECONFIG=/etc/kubernetes/admin.conf
EOF

# Enable various systemd services.
systemctl enable docker
systemctl enable reboot-api-node.service
systemctl enable reboot-api-node.timer
systemctl enable epoxy-extension-server.service
systemctl enable mount-data-api.service
systemctl enable create-control-plane.service
