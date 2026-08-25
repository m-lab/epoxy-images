#!/bin/bash

set -ux

# This script sets the CPU scaling governor to "performance" for every CPU,
# and writes out a Prometheus metric file which will be collected by the
# node_exporter textfile collector.
#
# The kernel parameter cpufreq.default_governor=performance (set in
# actions/stage3_ubuntu/stage2to3.json) should already have set the governor
# at boot. This script exists as a backstop, and to export a metric so that
# we will notice if the governor ever silently changes again:
# https://github.com/m-lab/ops-tracker/issues/1781
#
# If no scaling_governor files exist, the OS has no control over CPU
# frequency scaling and the metric will be 0. As of 2026-08 all platform
# machines (R630s and R640s alike) expose the governor to the OS, so this
# case is not expected in practice; the guard exists so that such a machine
# can never falsely report success.

METRIC_DIR=/cache/data/node-exporter
METRIC_FILE=$METRIC_DIR/set_cpu_governor.prom
METRIC_FILE_TEMP=$(mktemp)
mkdir -p $METRIC_DIR

# Writes the passed status code to a temporary metric file, then moves the
# temp metric file to the proper location, making it world readable.
function write_metric_file {
  local status=$1
  echo "node_cpu_scaling_governor_performance $status" > $METRIC_FILE_TEMP
  mv $METRIC_FILE_TEMP $METRIC_FILE
  chmod 644 $METRIC_FILE
}

shopt -s nullglob
governors=(/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor)

if [[ ${#governors[@]} -eq 0 ]]; then
  echo "CPU frequency scaling is not exposed to the OS. The BIOS may be" \
       "managing power itself, or the cpufreq driver failed to load."
  write_metric_file 0
  exit 0
fi

status=1
for governor in "${governors[@]}"; do
  echo "performance" > $governor || status=0
  if [[ $(cat $governor) != "performance" ]]; then
    status=0
  fi
done

write_metric_file $status
