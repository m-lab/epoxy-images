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

set -ux

USAGE="$0 <project> <nodelist file>"
PROJECT=${1:?Please provide a GCP project.}
NODE_LIST_FILE=${2:? Please provide a file with a list of nodes: ${USAGE}}

MAX_ERRORS=5
SLACK_WEBHOOK_URL=""

function send_slack_message() {
  local msg=$1

  if [[ -z $SLACK_WEBHOOK_URL ]]; then
    echo "No SLACK_WEBHOOK_URL configured for message: $msg"
    return
  fi

  # Increment the error counter.
  ERRORS=$(($ERRORS + 1))

  # Echo the message to the local terminal.
  echo "$msg"

  # Send the message to #op-deployment in Slack.
  curl -X POST -H 'Content-type: application/json' \
      --data "{'text':'$msg'}" \
      "$SLACK_WEBHOOK_URL"
}

ERRORS=0
while read -r node
do
  if [[ "$ERRORS" -gt "$MAX_ERRORS" ]]; then
    send_slack_message "Error count exceeded max error count of ${MAX_ERRORS}. Exiting."
    exit 1
  fi

  echo -ex "\n\nOPERATING ON NODE: ${node}"

  if [[ "$node" =~ ^# ]]; then
    echo "Node commented out. Skipping."
    continue
  fi

  # If the separator is a dash, then we assume this a v2 node name, else it's a
  # v1 node name.
  separator=${node:5:1}
  if [[ $separator == "-" ]]; then
    node_fqdn="${node}.${PROJECT}.measurement-lab.org"
  else
    node_fqdn="${node}.measurement-lab.org"
  fi

  # Discover the IP and password of the DRAC on this node.
  DRAC_INFO=$(bmctool get "$node")
  if [[ "$?" -ne "0" ]]; then
    send_slack_message "Failed to get DRAC info for ${node} using bmctool."
    continue
  fi
  DRAC_IP=$(echo "$DRAC_INFO" | jq -r '.address')
  DRAC_PASSWD=$(echo "$DRAC_INFO" | jq -r '.password')

  kubectl --context ${project} taint node ${node_fqdn} lame-duck=nic-first:NoSchedule

  # Give mlab-ns 2.5 minutes to notice the node is lame-ducked.
  sleep 150

  if ! docker run --rm --volume $PWD:/scripts -t epoxy-racadm \
      /scripts/boot_from_nic.sh ${DRAC_IP} ${DRAC_PASSWD}; then
    send_slack_message "Failed to set the NIC as first boot device for $node."
    continue
  fi

  # Wait for NDT to be fully functional again before taking the node out of
  # lame-duck mode. This assumes that NDT # listening on port 3001 is a good
  # stand-in for the vserver being up and # running.
  RETRIES=0
  REBOOT_FAILED="false"
  while ! nc -4 -z ndt.iupui.$node.measurement-lab.org 3001; do
    # If NDT isn't listening within 120 iterations of the loop (10 minutes, with a
    # sleep of 5s), then exit so that it doesn't hang forever.
    if [[ "$RETRIES" -gt 120 ]]; then
      REBOOT_FAILED="true"
      break
    fi
    sleep 5
    RETRIES=$(($RETRIES + 1))
  done

  if [[ "$REBOOT_FAILED" = "true" ]]; then
    send_slack_message "NDT still not back up after 10 minutes on node $node."
    continue
  fi

  kubectl --context ${project} taint node ${node_fqdn} lame-duck-

done < "$NODE_LIST_FILE"
