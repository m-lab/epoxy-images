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

# TODO (kinkade): Implement this some other way. An idea could be to add
# metadata to each API VM on creation, and the script that checks if the node
# needs to be rebooted can fetch this metadata at runtime to figure out whether
# to reboot the node or not.
#
# Write out the reboot day to a file in /etc. The reboot-node.service
# systemd unit will read the contents of this file to determine when to
# reboot the node.
# echo -n "${reboot_day}" > /etc/reboot-node-day

# Enable various systemd services.
systemctl enable docker
systemctl enable reboot-api-node.service
systemctl enable reboot-api-node.timer
systemctl enable token-server.service
systemctl enable bmc-store-password.service
