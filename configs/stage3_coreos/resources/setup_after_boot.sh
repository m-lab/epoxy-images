#!/bin/bash
#
# setup_after_boot.sh will run after boot and only once the network is online.
# The script runs as the root user.

echo "Running epoxy client"
/usr/bin/epoxy_client -action epoxy.stage3
