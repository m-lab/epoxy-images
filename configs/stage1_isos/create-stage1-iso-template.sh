#!/bin/bash
#
# create-stage1-iso-template.sh is a template for generating shell scripts to
# create a bootable stage1 ISO image from a suitable stage1 kernel.
#
# After template values are filled in, the resulting script constructs a kernel
# command line with epoxy network configuration and stage1 URL and finally
# generates an ISO image with the stage2_vmlinuz image and the construct kernel
# cmdline.

set -x

USAGE="$0 <sourcedir> <imagedir> <outputdir>"
SOURCE_DIR=${1:?Please provide the source directory root: $USAGE}
IMAGE_DIR=${2:?Error: specify input vmlinuz: $USAGE}
OUTPUT_DIR=${3:?Error: specify directory for output ISO: $USAGE}

# For the purposes of testing smaller IPv4 prefixes, allow CIDRs other than
# /26, but only in mlab-sandbox for now.
#
# TODO(kinkade): implement actual support for prefixes smaller than /26. Our
# goal is to be able to explicitly support prefixes smaller than /26, and the
# conditional below doesn't actually do this, but simply doesn't prevent the
# build from happening, which may have unexpected results.
if [[ $PROJECT != "mlab-sandbox" ]]; then
  if [[ "{{ipv4_netmask}}" != "255.255.255.192" ]] ; then
    echo 'Error: Sorry, unsupported netmask: {{ipv4_netmask}}'
    exit 1
  fi
fi

if [[ ! -f "${IMAGE_DIR}/stage1_kernel.vmlinuz" ]] ; then
    echo 'Error: vmlinuz image not found!'
    echo "Expected: ${IMAGE_DIR}/stage1_kernel.vmlinuz."
    exit 1
fi

# ARGS are kernel command line parameters included in the isolinux.cfg. During
# boot, parameters prefixed with "epoxy." are interpreted by the epoxy-client or
# other epoxy related network configuration scripts. All other parameters are
# interpreted by the kernel itself.
#
# Disable interface naming by the kernel. Preserves the use of `eth0`, etc.
ARGS="net.ifnames=0 "

# ePoxy server & project.
ARGS+="epoxy.project={{project}} "

# TODO: Legacy epoxy.ip= format. Remove once canonical form is supported.
ARGS+="epoxy.ip={{ipv4_address}}::{{ipv4_gateway}}:255.255.255.192:{{hostname}}:eth0:false:{{ipv4_dns1}}:{{ipv4_dns2}} "

# Canonical epoxy network configuration.
ARGS+="epoxy.hostname={{hostname}} "
ARGS+="epoxy.interface=eth0 "
ARGS+="epoxy.ipv4={{ipv4_address}}/{{ipv4_subnet}},{{ipv4_gateway}},{{ipv4_dns1}},{{ipv4_dns2}} "

if [[ "{{ipv6_enabled}}" == "true" ]] ; then
  ARGS+="epoxy.ipv6={{ipv6_address}}/64,{{ipv6_gateway}},{{ipv6_dns1}},{{ipv6_dns2}} "
else
  ARGS+="epoxy.ipv6= "
fi

# ePoxy stage1 URL.
ARGS+="epoxy.stage1=https://epoxy-boot-api.{{project}}.measurementlab.net/v1/boot/{{hostname}}/stage1.json "

# DRAC IPv4 address.
ARGS+="drac.ipv4={{drac_ipv4_address}}"

${SOURCE_DIR}/simpleiso -x "$ARGS" \
    -i "${IMAGE_DIR}"/stage1_initramfs.cpio.gz \
    "${IMAGE_DIR}/stage1_kernel.vmlinuz" \
    ${OUTPUT_DIR}/{{hostname}}_stage1.iso
