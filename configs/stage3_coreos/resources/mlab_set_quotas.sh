#!/bin/bash
#
# A simple script to facilitate setting XFS project quotas based on a
# configuration file.
#
# NOTE: Project IDs in the configuration file should never be removed or
# reused. If you want to disable quotas for a particular project/directory
# simply set the quota value to 0, which will effectively remove any quota,
# though accounting will still be happening.  In other words, only add new
# lines to the configuration file, don't remove them. You can recover from
# having removed something by simply rebooting the platform node, which will
# reformat the data mount, wiping out all accounting data with it.  From there
# you can start fresh.
#
# For the reasoning on why you see "sleep 0.1" before echo commands see:
# https://github.com/systemd/systemd/issues/2913

USAGE="$0 <config-file-path> <data-mount-path>"
CONFIG=${1:?Please provide a config file path: $USAGE}
DATA_MOUNT=${2:?Please provide a data mount path: $USAGE}
CONFIG_CACHED="/tmp/mlab_quotas"

if [[ ! -f "${CONFIG}" ]]; then
  echo "${CONFIG} does not exist. Exiting."
  sleep 0.1
  exit 0
fi

# If the quota configuration file has not been cached, then cache it. If it
# has, see if the current config files differs from the cached one. If they
# don't differ then just exit, as nothing needs to be done.
if [[ ! -f "${CONFIG_CACHED}" ]]; then
  cp "${CONFIG}" "${CONFIG_CACHED}"
else
  if diff "${CONFIG}" "${CONFIG_CACHED}" > /dev/null; then
    echo "Quota configuration file has not changed. Exiting."
    sleep 0.1
    exit 0
  fi
fi

# Reset /etc/projects and /etc/projid, which are used by the xfs_quota system.
cat /dev/null > /etc/projects
cat /dev/null > /etc/projid

# Iterate over lines in $CONFIG, setting quotas for each.
# An example line should look like this: 1:ndt:100g
#   Field 1: An arbitrary project ID.
#   Field 2: The name of the experiment.
#   Field 3: The quota value.
while IFS=: read -r -a line; do

  # Ignore comments.
  [[ "$line" =~ ^#.*$ ]] && continue

  # If there aren't exactly 3 values in the line, then skip it because it's not
  # a valid configuration.
  if [[ "${#line[@]}" -ne "3" ]]; then
    echo "Incorrect format in line '${line[@]}'. Skipping."
    sleep 0.1
    continue
  fi

  for v in "${line[@]}"; do
    project_id="${line[0]}"
    project_name="${line[1]}"
    project_quota="${line[2]}"
  done

  # The full path do the experiment's data directory.
  project_dir="${DATA_MOUNT}/$project_name"

  # Append to /etc/projects and /etc/projid.
  echo "${project_id}:${project_dir}" >> /etc/projects
  echo "${project_name}:${project_id}" >> /etc/projid

  # If $project_dir doesn't exist, then create it.
  mkdir -p "${project_dir}"

  # Be sure quotas are configured for the directory.
  xfs_quota -x -c "project -s ${project_name}" "${DATA_MOUNT}" > /dev/null

  # Set the quota for the experiment.
  xfs_quota -x -c "limit -p bhard=${project_quota} ${project_name}" \
      "${DATA_MOUNT}" > /dev/null

  echo "Set quota for experiment ${project_name} to ${project_quota}."
  sleep 0.1

done < "${CONFIG}"

