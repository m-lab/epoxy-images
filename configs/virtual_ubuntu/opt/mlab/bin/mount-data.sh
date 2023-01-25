#!/bin/bash
#
# Possibly format, and mount the persistent volume where local state data will
# be stored.

MOUNT_DIR="/mnt/local"
# A list of services that will be using this persistent volume, along with which
# subdirectory owner:group they require. Services listed here will get their own
# subdirectory in MOUNT_DIR. This is a bash associative array.
declare -A SERVICES=(
  ["prometheus"]="nobody:nogroup"
)

# Create stateful subdirectories, if they don't already exist, and set
# appropriate ownership of the subdirectory. This is apparently the awkward way
# in which one interates a bash associative array.
function create_subdirectories() {
  for key in "${!SERVICES[@]}"; do
    mkdir -p "${MOUNT_DIR}/${key}"
    chown "${SERVICES[$key]}" "${MOUNT_DIR}/${key}"
  done
}

# If for some reason the volume is already mounted, then go no farther.
if findmnt "$MOUNT_DIR"; then
  echo "$MOUNT_DIR is already mounted, doing nothing"
  create_subdirectories
  exit 0
fi

# This path should be the same for all platform cluster GCP-internal
# persistent volumes.
dev_path="/dev/disk/by-id/google-mlab-data"

# If the disk isn't formatted, then format it.
if ! blkid "$dev_path"; then
  echo "Formatting ${dev_path} as ext4"

  # These mkfs options were recommended by Google:
  # https://cloud.google.com/compute/docs/disks/add-persistent-disk#formatting
  mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "${dev_path}"

  if [[ $? -ne 0 ]]; then
    echo "Formatting ${dev_path} failed"
    exit 1
  fi
fi

mkdir -p "$MOUNT_DIR"

mount "$dev_path" "$MOUNT_DIR"

if [[ $? -ne 0 ]]; then
  echo "Mounting ${dev_path} to ${MOUNT_DIR} failed"
  exit 1
fi

create_subdirectories
