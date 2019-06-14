#/bin/bash
#
# A small script which will check the boot order of a machine via it's iDRAC.

set -euo pipefail

USAGE="$0 <nodelist file>"
NODE_LIST_FILE=${1:? Please provide a file with a list of nodes: ${USAGE}}

while IFS= read -r node
do
  DRAC_INFO=$(bmctool get "$node")
  DRAC_IP=$(echo "$DRAC_INFO" | jq -r '.address')
  DRAC_PASSWD=$(echo "$DRAC_INFO" | jq -r '.password')
  BOOTSEQ=$(docker run --rm -t epoxy-racadm \
      idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWD} \
      get bios.biosbootsettings.bootseq 2>&1 | grep BootSeq)
  echo "${node}: ${BOOTSEQ}"
done < $NODE_LIST_FILE
