#!/bin/bash
#
# setup_after_boot.sh will run after boot and only once the network is online.
# The script runs as the root user.

# Log all output.
exec 2> /var/log/setup_after_boot.log 1>&2

# Stop on any failure.
set -euxo pipefail

# Create a state directory for the IPAM host-local plugin (which is the IPAM
# plugin used by flannel). And create two symlinks to is named after the
# names of our two flannel networks. This causes both flannel networks to use
# a common state directory to avoid IP assignment conflics for pods.
mkdir -p /var/lib/cni/networks/flannel
ln -s flannel /var/lib/cni/networks/flannel-conf
ln -s flannel /var/lib/cni/networks/flannel-experiment-conf

echo "Running epoxy client"
/usr/bin/epoxy_client -action epoxy.stage3
