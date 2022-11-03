#!/bin/bash
#
# setup_stage1.sh generates Mellanox ROMs with per-machine configuration
# embedded in the ROM image (e.g. ipv4 address, gateway, hostname), references
# to the ePoxy server (e.g. boot-api-dot-mlab-staging.appspot.com), and a
# minimal iPXE script to load stage2 of the boot process.

set -x
set -e

SOURCE_DIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

USAGE="$0 <project> <builddir> <output dir> <mlxrom-config> <hostname-pattern> <embed-cert1,embed-cert2>"
PROJECT=${1:?Please specify the GCP project to contact: $USAGE}
BUILD_DIR=${2:?Please specify a build directory: $USAGE}
OUTPUT_DIR=${3:?Please specify an output directory: $USAGE}
CONFIG_DIR=${4:?Please specify a configuration directory: $USAGE}
CERTS=${5:?Please specify trusted certs to embed in ROM: $USAGE}

function generate_stage1_ipxe_scripts() {
  local build_dir=$1
  local config_dir=$2
  local output_dir=$3

  # Create all stage1.ipxe scripts.
  pushd ${build_dir}
    # TODO: replace host set with metadata service.
    # TODO: Replace curl with a native go-get once mlabconfig is rewritten in Go.
    curl --location "https://raw.githubusercontent.com/m-lab/siteinfo/master/cmd/mlabconfig.py" > \
        ./mlabconfig.py
    mkdir -p ${output_dir}
    python3 ./mlabconfig.py --format=server-network-config \
        --sites "${SITES}" \
        --physical \
        --project "${PROJECT}" \
        --label "project=${PROJECT}" \
        --template_input "${config_dir}/stage1-template.ipxe" \
        --template_output "${output_dir}/stage1-{{hostname}}.ipxe"
  popd
}

function build_roms() {
  local ipxe_src=$1
  local stage1_config_dir=$2
  local debug=$3
  local certs=$4
  local rom_output_dir=$5

  local extra_cflags=
  local procs=`getconf _NPROCESSORS_ONLN`

  # 15b3 is the vendor ID for Mellanox Technologies
  # 1003 is the device ID for the ConnectX-3
  # 1007 is the device ID for the ConnectX-3Pro
  for device in 15b31003 15b31007; do
    pushd ${ipxe_src}
      # Use the git short commit of HEAD as the version string for the images.
      version=$(git rev-parse --short HEAD)

      if [[ $device == "15b31003" ]]; then
        device_name="ConnectX-3"
      else
        device_name="ConnectX-3Pro"
      fi

      # NOTE: clean the build environment between devices. Without resetting,
      # ROMs for the ConnectX-3Pro have the wrong device ID.
      make clean
      rm -rf bin

      for stage1 in `ls ${stage1_config_dir}/*.ipxe` ; do
        # Extract the hostname from the filename.
        hostname=${stage1##*stage1-}
        hostname=${hostname%%.ipxe}

        # The generated ROM file is the device name.
        make -j ${procs} bin/${device}.mrom \
            EXTRA_CFLAGS="-D__BUILD_VERSION__=$version" \
            DEBUG=${debug} \
            TRUST=${certs} \
            EMBED=${stage1} \
            NO_WERROR=1

        # Copy it to a structured location.
        # Note: the update image depends on this structure to locate an image.
        mkdir -p ${rom_output_dir}/${version}/${device_name}/
        cp bin/${device}.mrom ${rom_output_dir}/${version}/${device_name}/${hostname}.mrom
      done
    popd
  done
  # Remove old files to prevent regenerating ROMs during multiple builds.
  rm -f ${stage1_config_dir}/*.ipxe
}


function copy_roms_to_output() {
  local build_dir=$1
  local output_dir=$2

  mkdir -p "${output_dir}"
  # Copy files to output.
  rsync -ar "${build_dir}" "${output_dir}"
  # Assure that the output files are readable.
  chmod -R go+r "${output_dir}"
}


# Extra debug symbols.
#
# Debug symbols can be enabled on a per-module bases (i.e. strip ".o" from
# filename).
#
# Note: it's possible to generate a ROM image that is too large if too many
# debug symbols are enabled.
#
# For example, to debug TLS negotiation using the embedded trusted certificates,
# I started with these: DEBUG=tls,x509,certstore
DEBUG=

SCRIPTDIR=$( mktemp -d -t stage1_scripts.XXXXXX )

# Clone the ipxe sources.
git clone https://github.com/ipxe/ipxe.git
ipxe_source=/workspace/ipxe/src

generate_stage1_ipxe_scripts \
    ${BUILD_DIR} \
    ${CONFIG_DIR} \
    "${SCRIPTDIR}"

build_roms \
    "${ipxe_source}" \
    "${SCRIPTDIR}" \
    "${DEBUG}" \
    "${CERTS}" \
    "${BUILD_DIR}/stage1_mlxrom"

rm -rf "${SCRIPTDIR}"
rm -rf "${ipxe_source}"

copy_roms_to_output \
    ${BUILD_DIR}/stage1_mlxrom/ \
    ${OUTPUT_DIR}/stage1_mlxrom
