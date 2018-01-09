#!/bin/bash
#
# create_update_iso.sh generates a bootable ISO image from the kernel and
# initram built by setup_stage3_mlxupdate.sh build scripts. Given the machine
# hostname, IPv4 address and gateway, this script constructs an epoxy network
# configuration for the kernel command line, which allows standard network
# scripts to setup the network at boot time.

USAGE="$0 <hostname> <ipv4-address> <ipv4-gateway>"
HOSTNAME=${1:?Error: please specify the server FQDN: $USAGE}
IPV4_ADDR=${2:?Error: please specify the server IPv4 address with mask, e.g. 192.168.0.1/24: $USAGE}
GW=${3:?Error: please specify the server IPv4 gateway address: $USAGE}

if [[ ! -f $PWD/build/initramfs_stage3_mlxupdate.cpio.gz || \
      ! -f $PWD/build/vmlinuz_stage3_mlxupdate ]] ; then
    echo 'Error: vmlinuz and initramfs images not found!'
    echo "Expected: $PWD/build/initramfs_stage3_mlxupdate.cpio.gz"
    echo "Expected: $PWD/build/vmlinuz_stage3_mlxupdate"
    exit 1
fi
# Disable interface naming by the kernel. Preserves the use of `eth0`, etc.
ARGS="net.ifnames=0 "

# TODO: Legacy epoxy.ip= format. Remove once canonical form is supported.
# Note: Strip the netmask and hard code it instead.
ARGS+="epoxy.ip=${IPV4_ADDR%%/*}::${GW}:255.255.255.192:${HOSTNAME}:eth0:false:8.8.8.8:8.8.4.4 "

# Canonical epoxy network configuration.
ARGS+="epoxy.hostname=${HOSTNAME} "
ARGS+="epoxy.interface=eth0 "
ARGS+="epoxy.ipv4=${IPV4_ADDR},${GW},8.8.8.8,8.8.4.4 "

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
