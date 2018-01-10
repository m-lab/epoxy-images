#!/bin/bash
#
# create_update_iso.sh generates a bootable ISO image from the kernel and
# initram built by setup_stage3_mlxupdate.sh build scripts. Given the machine
# hostname, IPv4 address and gateway, this script constructs an epoxy network
# configuration for the kernel command line, which allows standard network
# scripts to setup the network at boot time.

USAGE="$0 <hostname> <ipv4-address>/<mask> <ipv4-gateway> [<dns1>][, <dns2>]"
HOSTNAME=${1:?Error: please specify the server FQDN: $USAGE}
IPV4_ADDR=${2:?Error: please specify the server IPv4 address with mask: $USAGE}
IPV4_GATEWAY=${3:?Error: please specify the server IPv4 gateway address: $USAGE}
DNS1=${4:-8.8.8.8}
DNS2=${5:-8.8.4.4}

if [[ ! -f $PWD/build/initramfs_stage3_mlxupdate.cpio.gz || \
      ! -f $PWD/build/vmlinuz_stage3_mlxupdate ]] ; then
    echo 'Error: vmlinuz and initramfs images not found!'
    echo "Expected: $PWD/build/initramfs_stage3_mlxupdate.cpio.gz"
    echo "Expected: $PWD/build/vmlinuz_stage3_mlxupdate"
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
URL=https://storage.googleapis.com/epoxy-mlab-staging
# TODO: Only encode the base URL. The download script should detect the device
# model and construct the full path based on the system hostname.
ARGS+="epoxy.mrom=$URL/mellanox-roms/3.4.800/ConnectX-3.mrom/${HOSTNAME}.mrom "


SCRIPTDIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )
${SCRIPTDIR}/simpleiso -x "$ARGS" \
    -i $PWD/build/initramfs_stage3_mlxupdate.cpio.gz \
    $PWD/build/vmlinuz_stage3_mlxupdate \
    $PWD/build/${HOSTNAME}_mlxupdate.iso
