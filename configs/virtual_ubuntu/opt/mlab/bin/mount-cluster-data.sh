#!/bin/bash

MOUNT_DIR="/mnt/cluster-data"

# If for some reason the volume is already mounted, then go no farther.
if findmnt "$MOUNT_DIR"; then
  echo "$MOUNT_DIR is already mounted, doing nothing"
  exit 0
fi

dev_name=$(
  curl -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cluster_data" \
    | jq -r '.machine_attributes.disk_dev_name_data'
)
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

# Create subdirectories for k8s and etcd
# /etc/kubernetes will be a symlink to this.
mkdir -p "${MOUNT_DIR}/kubernetes"
# /var/lib/etcd will be a symlink to this.
mkdir -p "${MOUNT_DIR}/etcd"
