#!/bin/bash
#
# setup_after_boot.sh will run after boot and only once the network is online.
# The script runs as the root user.

# TODO: do something useful.
echo "After Boot Script!"
date > /tmp/after_boot.success
ifconfig >> /tmp/after_boot.success
whoami >> /tmp/after_boot.success
echo "ABS: success!"
