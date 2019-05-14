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

if [[ "{{netmask}}" != "255.255.255.192" ]] ; then
  echo 'Error: Sorry, unsupported netmask: {{netmask}}'
  exit 1
fi
mask=26

if [[ ! -f "${IMAGE_DIR}/stage2_vmlinuz" ]] ; then
    echo 'Error: vmlinuz images not found!'
    echo "Expected: stage2_vmlinuz"
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
ARGS+="epoxy.ip={{ip}}::{{gateway}}:255.255.255.192:{{hostname}}:eth0:false:{{dns1}}:8.8.4.4 "

# Canonical epoxy network configuration.
ARGS+="epoxy.hostname={{hostname}} "
ARGS+="epoxy.interface=eth0 "
ARGS+="epoxy.ipv4={{ip}}/${mask},{{gateway}},{{dns1}},8.8.4.4 "

if [[ "{{ipv6_enabled}}" == "true" ]] ; then
  ARGS+="epoxy.ipv6={{ipv6_address}}/64,{{ipv6_gateway}},{{ipv6_dns1}},{{ipv6_dns2}} "
else
  ARGS+="epoxy.ipv6= "
fi

# ePoxy stage1 URL.
ARGS+="epoxy.stage1=https://epoxy-boot-api.{{project}}.measurementlab.net/v1/boot/{{hostname}}/stage1.json"

${SOURCE_DIR}/simpleiso -x "$ARGS" \
    -i "${IMAGE_DIR}"/initramfs_stage1_minimal.cpio.gz \
    "${IMAGE_DIR}/vmlinuz_stage1_minimal" \
    ${OUTPUT_DIR}/{{hostname}}_stage1.iso
