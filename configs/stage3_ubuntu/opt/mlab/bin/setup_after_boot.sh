#!/bin/bash
#
# setup_after_boot.sh will run after boot and only once the network is online.
# The script runs as the root user.

# Log all output.
exec 2> /var/log/setup_after_boot.log 1>&2

# Stop on any failure.
set -euxo pipefail

echo "Running epoxy client"
/usr/bin/epoxy_client -action epoxy.stage3

