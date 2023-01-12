#!/bin/bash
#
# This script gets uploaded and executed on the temporary VM that Packer
# creates when generating custom images. It should do everything necessary to
# prepare the custom image's environment for normal machine.

set -euxo pipefail

# The directory where machine metadata will be written, possibly consumed by
# experiments.
mkdir -p /var/local/metadata

# If this directory doesn't exist, then the kubelet complains bitterly,
# polluting the logs terribly.
mkdir -p /etc/kubernetes/manifests

# Enable systemd units
systemctl enable check-reboot.service
systemctl enable check-reboot.timer
systemctl enable configure-tc-fq.service
systemctl enable write-metadata.service
systemctl enable join-cluster.service
