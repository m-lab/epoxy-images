#!/bin/bash
#
# This script reboots control plane machines once a week. It will only reboot
# the machine if the control plane etcd cluster is healthy, and if the current
# day is the configured reboot day for that particular machine.

REBOOT_DAY=$(cat /etc/reboot-node-day)
TODAY=$(date +%a)

source /root/.profile

# Members are listed whether they are healthy or not.
ETCD_ENDPOINTS=$(/opt/bin/etcdctl member list | egrep -o 'https://[0-9.]+:2379' | paste -s -d, -)
export ETCDCTL_ENDPOINTS="${ETCD_ENDPOINTS}"

# Currently healthy endpoints are reported on stderr, along with actual
# errors: https://github.com/etcd-io/etcd/pull/11322. That issue is closed
# and a related PR merged, but the fix is not yet part of the current
# Ubuntu version 3.4.7 (2020-07-16). When it is in the curernt Ubuntu
# release then this code can be refactored.
ETCD_HEALTHY_COUNT=$(/opt/bin/etcdctl endpoint health 2>&1 \
    | grep -P '(?<!un)healthy' | wc -l)

if [[ "${REBOOT_DAY}" != "${TODAY}" ]]; then
  echo "Reboot day ${REBOOT_DAY} doesn't equal today: ${TODAY}. Not rebooting."
  exit 0
fi

if [[ "${ETCD_HEALTHY_COUNT}" -lt "3" ]]; then
  echo "There are less than 3 healthy etcd cluster members. Not rebooting."
  exit 1
fi

# While we are at it, update all system packages.
DEBIAN_FRONTEND=noninteractive apt full-upgrade --yes
echo "Reboot day ${REBOOT_DAY} equals today: ${TODAY}. Rebooting node."

/sbin/reboot

