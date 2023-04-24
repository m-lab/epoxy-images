#!/bin/bash
#
# Possibly formats, and mounts the API/control-plane persistent volume. This
# volume is where all persistent state data for kubernetes, etcd and the
# kubelet will be stored.

MOUNT_DIR="/mnt/cluster-data"

# Create stateful subdirectories, if they don't already exist.
function create_subdirectories() {
  # /etc/kubernetes will be a symlink to this.
  mkdir -p "${MOUNT_DIR}/kubernetes"
  # /var/lib/kubelet will be symlink to this.
  mkdir -p "${MOUNT_DIR}/kubelet"
}

# If for some reason the volume is already mounted, then go no farther.
if findmnt "$MOUNT_DIR"; then
  echo "$MOUNT_DIR is already mounted, doing nothing"
  create_subdirectories
  exit 0
fi

dev_name=$(
  curl -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cluster_data" \
    | jq -r '.machine_attributes.disk_dev_name_data'
)
if [[ -z $dev_name ]]; then
  echo "Failed to determine the persistent disk device name"
  exit 1
fi
dev_path="/dev/disk/by-id/google-${dev_name}"

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
