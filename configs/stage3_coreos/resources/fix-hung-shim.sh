#!/bin/bash
#
# fix-hung-shim.sh checks whether the host container appears to be hung during
# shutdown. Before fix-hung-shim kills any current processes, it must observe
# the hung process twice with at least 15min between checks.
#
# TODO(https://github.com/m-lab/k8s-support/issues/230): Delete this script once
# issue is fixed.

set -e

# Persistent files.
STATEDIR=/var/cache/fix-hung-shim
mkdir --parents "${STATEDIR}"

# Temp files.
TEMPDIR=$( mktemp -d )

# Count the current number of host containers.
docker ps > $TEMPDIR/host.log
# If this is the very first time, copy the log file and exit.
if [[ ! -f ${STATEDIR}/host.log ]] ; then
  mv --force $TEMPDIR/host.log $STATEDIR/host.log
  rm -rf $TEMPDIR
  exit 0
fi

# The temporary and previous host.log files should both exist.
CURR_COUNT=$( cat $TEMPDIR/host.log | grep host | wc --lines )
PREV_COUNT=$( cat $STATEDIR/host.log | grep host | wc --lines )

# Runtimes.
CURR_TIME=$( date +%s )
PREV_TIME=$( stat --format=%Y ${STATEDIR}/host.log )

# The last two checks counted 1 process, and it's been at least 15min.
if [[ $PREV_COUNT -eq 1 ]] && \
   [[ $CURR_COUNT -eq 1 ]] && \
   [[ $(( $CURR_TIME - $PREV_TIME )) -ge 900 ]] ; then

  # Lookup container id for hung shim process.
  container_id=$( cat $TEMPDIR/host.log | grep host | awk '{print $1}' )
  if [[ -z "$container_id" ]] ; then
    echo "Failed to extract host container id"
    exit 1
  fi
  # Kill all process ids for commands matching container_id.
  pgrep --full $container_id | xargs kill -9

  # Remove old state.
  rm -f $STATEDIR/host.log
fi

# Only rotate the host log every 15min.
if [[ $(( $CURR_TIME - $PREV_TIME )) -ge 900 ]] ; then
  mv --force $TEMPDIR/host.log $STATEDIR/host.log
fi

# Clean up tempdir.
rm -rf $TEMPDIR
