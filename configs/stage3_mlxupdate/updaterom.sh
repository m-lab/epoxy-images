#!/bin/bash
#
# updaterom.sh is the entrypoint for downloading a ROM image and flashing it
# to the local NIC.
#
# The ROM location is expected to be present in the kernel cmdline with the
# name epoxy.mrom=https://... to a location in GCS or similar.
#
# TODO: rewrite as Go command, e.g. possibly as part of epoxy-client.

set -x
set -e

baseurl=
for field in $( cat /proc/cmdline ) ; do
  if [[ "epoxy.mrom" == "${field%%=*}" ]] ; then
    baseurl=${field##epoxy.mrom=}
    break
  fi
done

if test -z "$baseurl" ; then
  echo "ERROR: no ROM URL found. Giving up."
  exit 1
fi

# Detect the device to identify the model name.
# Note: Model names are derived from ipxe build targets, so should not change.
# TODO: can this be simpler?
if [[ -e /dev/mst/mt4099_pci_cr0 ]] ; then
    # ConnectX3, model 4099/0x1003
    MODEL=ConnectX-3
elif [[ -e /dev/mst/mt4103_pci_cr0 ]] ; then
    # ConnectX3-Pro, model 4103/0x1007
    MODEL=ConnectX-3Pro
else
    echo 'ERROR: failed to identify the device model!'
    exit 1
fi

# Construct the full ROM URL using the model and hostname.
romurl=${baseurl}/${MODEL}/$( hostname ).mrom
echo "Downloading ROM"
wget -O epoxy.mrom "${romurl}"
if ! test -f epoxy.mrom || ! test -s epoxy.mrom ; then
    echo "Error: failed to download epoxy.mrom from ${romurl}"
    exit 1
fi

echo "Updating ROM"
/usr/local/util/flashrom.sh epoxy.mrom

# TODO(soltesz): use `epoxy-client --complete` to acknowldge this step.
echo "WARNING: Not acknowledging success. Taking no action."
# TODO: restart system on success.
