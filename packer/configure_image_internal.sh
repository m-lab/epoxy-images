#!/bin/bash
#
# This script gets uploaded and executed on the temporary VM that Packer
# creates when generating custom images. It should do everything necessary to
# prepare the custom image's environment for normal machine.

set -euxo pipefail

# If this directory doesn't exist, then the kubelet complains bitterly,
# polluting the logs terribly.
mkdir -p /etc/kubernetes/manifests

# Enable systemd units
systemctl enable join-cluster-internal.service
systemctl enable mount-data.service
