#!/bin/bash

# The maximum amount of time, in days, that a machine can be up before it gets
# automatically rebooted.
MAX_DAYS_UP=60
REBOOT_SENTINEL_FILE=/var/run/mlab-reboot

# Check if the sentinel file already exists. If so, do nothing and exit.
if [[ -f $REBOOT_SENTINEL_FILE ]]; then
  echo "Reboot sentinel file ${REBOOT_SENTINEL_FILE} already exists. Exiting..."
  exit
fi

# The first field in /proc/uptime is the machine's uptime in seconds. Here we
# convert that to days to make things easier to understand for people.
days_up=$(awk '{print int($1 / 60 / 60/ 24)}' /proc/uptime)
if [[ $days_up -gt $MAX_DAYS_UP ]]; then
  echo "Uptime of ${days_up}d exceeds MAX_DAYS_UP=${MAX_DAYS_UP}. Triggering reboot..."
  touch "$REBOOT_SENTINEL_FILE"
else
  echo "Uptime of ${days_up}d does not exceed MAX_DAYS_UP=${MAX_DAYS_UP}. Doing nothing..."
fi

