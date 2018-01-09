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

romurl=
for field in $( cat /proc/cmdline ) ; do
  if [[ "epoxy.mrom" == "${field%%=*}" ]] ; then
    romurl=${field##epoxy.mrom=}
    break
  fi
done

if test -z "$romurl" ; then
  echo "WARNING: no ROM URL found. Giving up."
  exit 1
fi

# TODO: discover the device type, and download the appropriate rom image from a
# base URL.
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
