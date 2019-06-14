#!/bin/bash
# 
# A wrapper script for the boot_from_nic.sh script to orchestrate reading a
# node list, putting a node into lame-duck mode, running the boot_from_nic.sh
# script and then making sure the node came back up before moving on to the
# next node.
# 
# This script makes a *lot* of assumptions about the filesystem layout and tools
# that are in your path, but this is probably okay because once the platform is
# converted to booting from ePoxy, we likely won't ever need this script again.
#
# NOTE: this script expects the node list to use short names (e.g.,
# mlab1.abc01) and will *not* work with long node names.

set -euo pipefail

USAGE="$0 <nodelist file>"
NODE_LIST_FILE=${1:? Please provide a file with a list of nodes: ${USAGE}}

while read -r node
do
  echo -e "\n\nOPERATING ON NODE: ${node}"

  if [[ "$node" =~ ^# ]]; then
    echo "Node commented out. Skipping."
    continue
  fi

  # Discover the IP and password of the DRAC on this node.
  DRAC_INFO=$(bmctool get "$node")
  DRAC_IP=$(echo "$DRAC_INFO" | jq -r '.address')
  DRAC_PASSWD=$(echo "$DRAC_INFO" | jq -r '.password')

  # Put the node into lame-duck mode.
  pushd $HOME/git/mlabops/ansible/lame-duck
  ansible-playbook -i $node, lame_duck.yaml --extra-vars "mode=set"
  popd

  # Give mlab-ns 2.5 minutes to notice the node is in lame-duck mode
  sleep 150

  docker run --rm --volume $PWD:/scripts -t epoxy-racadm \
      /scripts/boot_from_nic.sh ${DRAC_IP} ${DRAC_PASSWD}

  # Wait for NDT to be fully functional again before taking the node out of
  # lame-duck mode. This assumes that NDT # listening on port 3001 is a good
  # stand-in for the vserver being up and # running.
  RETRIES=0
  while ! nc -4 -z ndt.iupui.$node.measurement-lab.org 3001; do
    # If NDT isn't listening within 120 iterations of the loop (10 minutes, with a
    # sleep of 5s), then exit so that it doesn't hang forever.
    if [[ "$RETRIES" -gt 120 ]]; then
      echo "NDT still not back up after 10 minutes on node $node. Giving up."
      exit 1
    fi
    sleep 5
    RETRIES=$(($RETRIES + 1))
  done

  # Take the node out of lame-duck mode.
  pushd $HOME/git/mlabops/ansible/lame-duck
  ansible-playbook -i $node, lame_duck.yaml --extra-vars "mode=unset"
  popd

done < "$NODE_LIST_FILE"

