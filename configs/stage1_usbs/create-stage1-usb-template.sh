#!/bin/bash
#
# create-stage1-usb-template.sh is a template for generating shell scripts to
# create a bootable stage1 USB image from a suitable stage1 kernel.
#
# After template values are filled in, the resulting script constructs a kernel
# command line with epoxy network configuration and stage1 URL and finally
# generates a USB image with the stage1_minimal image.

set -x

USAGE="$0 <sourcedir> <imagedir> <outputdir>"
SOURCE_DIR=${1:?Please provide the source directory root: $USAGE}
IMAGE_DIR=${2:?Error: specify input vmlinuz: $USAGE}
OUTPUT_DIR=${3:?Error: specify directory for output USB: $USAGE}

if [[ "{{ipv4_netmask}}" != "255.255.255.192" ]] ; then
  echo 'Error: Sorry, unsupported netmask: {{ipv4_netmask}}'
  exit 1
fi

if [[ ! -f "${IMAGE_DIR}/vmlinuz_stage1_minimal" ]] ; then
    echo 'Error: vmlinuz images not found!'
    echo "Expected: vmlinuz_stage1_minimal"
    exit 1
fi

# ARGS are kernel command line parameters included in the syslinux.cfg. During
# boot, parameters prefixed with "epoxy." are interpreted by the epoxy-client or
# other epoxy related network configuration scripts. All other parameters are
# interpreted by the kernel itself.
#
# Disable interface naming by the kernel. Preserves the use of `eth0`, etc.
ARGS="net.ifnames=0 "

# ePoxy server & project.
ARGS+="epoxy.project={{project}} "

# Site uplink speed.
ARGS+="epoxy.uplink_speed={{uplink_speed}} "

# TODO: Legacy epoxy.ip= format. Remove once canonical form is supported.
ARGS+="epoxy.ip={{ipv4_address}}::{{ipv4_gateway}}:255.255.255.192:{{hostname}}:eth0:false:{{ipv4_dns1}}:{{ipv4_dns2}} "

# Canonical epoxy network configuration.
ARGS+="epoxy.hostname={{hostname}} "
ARGS+="epoxy.interface=eth0 "
ARGS+="epoxy.ipv4={{ipv4_address}}/{{ipv4_subnet}},{{ipv4_gateway}},{{ipv4_dns1}},{{ipv4_dns2}} "

if [[ "{{ipv6_enabled}}" == "true" ]] ; then
  ARGS+="epoxy.ipv6={{ipv6_address}}/{{ipv6_subnet}},{{ipv6_gateway}},{{ipv6_dns1}},{{ipv6_dns2}} "
else
  ARGS+="epoxy.ipv6= "
fi

# ePoxy stage1 URL.
ARGS+="epoxy.stage1=https://epoxy-boot-api.{{project}}.measurementlab.net/v1/boot/{{hostname}}/stage1.json"


# TODO: update to use stage2 kernels when they support UEFI boot fully.
# ${SOURCE_DIR}/simpleusb -x "$ARGS" "${IMAGE_DIR}/stage2_vmlinuz" \
#    ${OUTPUT_DIR}/{{hostname}}_stage1.usb

# Generate stage1 USB image.
"${SOURCE_DIR}"/simpleusb -x "$ARGS" \
    -i "${IMAGE_DIR}"/initramfs_stage1_minimal.cpio.gz \
    "${IMAGE_DIR}"/vmlinuz_stage1_minimal \
    "${OUTPUT_DIR}"/{{hostname}}_stage1.fat16.gpt.img
