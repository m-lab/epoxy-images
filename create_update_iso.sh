#!/bin/bash
#
# create_update_iso.sh generates a bootable ISO image from the kernel and
# initram built by setup_stage3_update.sh build scripts. Given the machine
# hostname, IPv4 address and gateway, this script constructs an epoxy network
# configuration for the kernel command line, which allows standard network
# scripts to setup the network at boot time.

set -x

USAGE="$0 <project> <image-dir> <rom-version> <hostname> <ipv4-address>/<mask> <ipv4-gateway> [<dns1>][, <dns2>]"
PROJECT=${1:?Please provide the GCP Project}
IMAGE_DIR=${2:?Error: specify input directory with vmlinuz and initram: $USAGE}
OUTPUT_DIR=${3:?Error: specify directory for output ISO: $USAGE}
ROM_VERSION=${4:?Error: please specify the ROM version as "3.4.800": $USAGE}
HOSTNAME=${5:?Error: please specify the server FQDN: $USAGE}
IPV4_ADDR=${6:?Error: please specify the server IPv4 address with mask: $USAGE}
IPV4_GATEWAY=${7:?Error: please specify the server IPv4 gateway address: $USAGE}
DNS1=${8:-8.8.8.8}
DNS2=${9:-8.8.4.4}

if [[ ! -f ${IMAGE_DIR}/initramfs_stage3_update.cpio.gz || \
      ! -f ${IMAGE_DIR}/vmlinuz_stage3_update ]] ; then
    echo 'Error: vmlinuz and initramfs images not found!'
    echo "Expected: ${IMAGE_DIR}/initramfs_stage3_update.cpio.gz"
    echo "Expected: ${IMAGE_DIR}/vmlinuz_stage3_update"
    exit 1
fi

# ARGS are kernel command line parameters included in the isolinux.cfg. During
# boot, parameters prefixed with "epoxy." are interpreted by the epoxy-client or
# other epoxy related network configuration scripts. All other parameters are
# interpreted by the kernel itself.
#
# Disable interface naming by the kernel. Preserves the use of `eth0`, etc.
ARGS="net.ifnames=0 "

# TODO: Legacy epoxy.ip= format. Remove once canonical form is supported.
# Note: Strip the netmask and hard code it to /26 instead.
ARGS+="epoxy.ip=${IPV4_ADDR%%/*}::${IPV4_GATEWAY}:255.255.255.192:${HOSTNAME}:"
ARGS+="eth0:false:${DNS1}:${DNS2} "

# Canonical epoxy network configuration.
ARGS+="epoxy.hostname=${HOSTNAME} "
ARGS+="epoxy.interface=eth0 "
ARGS+="epoxy.ipv4=${IPV4_ADDR},${IPV4_GATEWAY},${DNS1},${DNS2} "

# Add URL to the epoxy ROM image.
URL=https://storage.googleapis.com/epoxy-${PROJECT}
# Note: Only encode the base URL. The download script detects the device
# model and constructs the full path ROM based on the system hostname.
ARGS+="epoxy.mrom=$URL/stage1_mlxrom/${ROM_VERSION} "

# Note: Add a epoxy.stage3 action so the update can automatically run
# updaterom.sh after boot.
ARGS+="epoxy.stage3=$URL/stage3_update/stage3post.json "

SOURCE_DIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )
${SOURCE_DIR}/simpleiso -x "$ARGS" \
    -i ${IMAGE_DIR}/initramfs_stage3_update.cpio.gz \
    ${IMAGE_DIR}/vmlinuz_stage3_update \
    ${OUTPUT_DIR}/${HOSTNAME}_update.iso
