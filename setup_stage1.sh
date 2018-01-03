#!/bin/bash
#
# setup_stage1.sh generates Mellanox ROMs with per-machine configuration
# embedded in the ROM image (e.g. ipv4 address, gageway, hostname), references
# to the ePoxy server (e.g. boot-api-dot-mlab-staging.appspot.com), and a
# minimal iPXE script to load stage2 of the boot process.

set -x
set -e

SCRIPTDIR=$( realpath $( dirname "${BASH_SOURCE[0]}" ) )

USAGE="$0 <builddir> <mlx-rom-config> <hostname-pattern> <rom-version> <embed-cert1,embed-cert2>"
BUILD_DIR=${1:?Please specify a build directory: $USAGE}
CONFIG_DIR=${2:?Please specify a configuration directory: $USAGE}
HOSTNAMES=${3:?Please specify a hostname pattern: $USAGE}
VERSION=${4:?Please specify the ROM version as "3.4.800": $USAGE}
CERTS=${5:?Please specify trusted certs to embed: $USAGE}

# unpack checks whether the given directory exists and if it does not unpacks
# the given tar archive (which should create the directory).
function unpack () {
  local dir=$1
  local tgz=$2
  if ! test -d $dir ; then
    if ! test -f $tgz ; then
      echo "error: no such file $tgz"
      exit 1
    fi
    tar xvf $tgz
  fi
}


function prepare_flexboot_source() {
  local build_dir=$1
  local config_dir=$2
  local archive_path=$3
  local canonical_name=$4

  pushd ${build_dir}
    if test -d ${canonical_name} ; then
      # The following steps were already taken. Don't repeat them.
      return
    fi
    version=$( basename ${archive_path} .tar.gz )
    unpack ${version} ${archive_path}
    pushd ${version}/src
      # Use gcc-4.8 since gcc-5 (default in xenial) causes build failure.
      sed -i -e 's/ gcc/ gcc-4.8/g' -e 's/)gcc/)gcc-4.8/g' Makefile

      # Add the 'driver_version' definition to flexboot source.
      git apply ${config_dir}/romprefix.S.diff

      # Enable TLS configuration and any other non-standard options.
      git apply ${config_dir}/config_general.h.diff
    popd

    # Move the working directory to the canonical name to signal we're done.
    mv ${version} ${canonical_name}
  popd
}


function generate_stage1_ipxe_scripts() {
  local build_dir=$1
  local config_dir=$2
  local hostname_pattern=$3
  local output_dir=$4

  # Create all stage1.ipxe scripts.
  pushd ${build_dir}
    # TODO: replace host set with metadata service.
    test -d operator || git clone https://github.com/m-lab/operator
    pushd operator/plsync
      mkdir -p ${output_dir}
      ./mlabconfig.py --format=server-network-config \
          --select "${hostname_pattern}" \
          --template_input "${config_dir}/stage1-template.ipxe" \
          --template_output "${output_dir}/stage1-{{hostname}}.ipxe"
    popd
  popd
}


# define reads a heredoc into the named variable. The variable will be global.
function define() {
  local varname=$1
  #  -r     Backslash does not act as an escape character.
  #  -d     The first character is used to terminate the input line. We use the
  #         empty string, so line input is not terminated until "EOF".
  # TODO: why do we set IFS?
  IFS='\n' read -r -d '' ${varname} || true;
}

function get_extra_flags() {
  local target=$1
  local version=$2
  local device_id=

  local major=${version%%.*}
  local sub=${version%.*} ; sub=${sub#*.}
  local minor=${version##*.}

  major=$( printf "%04x" $major )
  sub=$( printf "%04x" $sub )
  minor=$( printf "%04x" $minor )

  case $target in

    ConnectX-3.mrom)
      device_id=0x1003
      ;;

    ConnectX-3Pro.mrom)
      device_id=0x1007
      ;;

    *)
      echo "Error: unsupported target name: $target" 1>&2
      exit 1
      ;;
  esac

  define extra_flags <<EOM
    -Wno-error=strict-aliasing
    -Wno-error=address
    -Wno-pointer-to-int-cast
    -Wno-error=maybe-uninitialized
    -DMLX_BUILD
    -DDEVICE_CX3
    -DFLASH_CONFIGURATION
    -D__MLX_0001_MAJOR_VER_=0x0010${major}
    -D__MLX_MIN_SUB_MIN_VER_=0x${sub}${minor}
    -D__MLX_DEV_ID_00ff=${device_id}00ff
    -D__BUILD_VERSION__=\"$version\"
    -Idrivers/infiniband/mlx_utils_flexboot/include/
    -Idrivers/infiniband/mlx_utils/include/
    -Idrivers/infiniband/mlx_utils/include/public/
    -Idrivers/infiniband/mlx_utils/include/private/
    -Idrivers/infiniband/mlx_nodnic/include/
    -Idrivers/infiniband/mlx_nodnic/include/public/
    -Idrivers/infiniband/mlx_nodnic/include/private/
    -Idrivers/infiniband/mlx_utils_flexboot/tests/include/
    -Idrivers/infiniband/mlx_utils/mlx_lib/mlx_reg_access/
    -Idrivers/infiniband/mlx_utils/mlx_lib/mlx_nvconfig/
    -Idrivers/infiniband/mlx_utils/mlx_lib/mlx_vmac/
EOM
  echo $extra_flags
}


function build_roms() {
  local flexboot_src=$1
  local stage1_config_dir=$2
  local version=$3
  local debug=$4
  local certs=$5
  local rom_output_dir=$6

  local extra_cflags=
  local procs=`getconf _NPROCESSORS_ONLN`

  for stage1 in `ls ${stage1_config_dir}/*.ipxe` ; do
    # Extract the hostname from the filename.
    hostname=${stage1##*stage1-}
    hostname=${hostname%%.ipxe}

    pushd ${flexboot_src}
      # TODO: select image type more intelligently.
      for device in ConnectX-3.mrom ConnectX-3Pro.mrom ; do
        # Note: this is currently very inefficient.
        # The flexboot build scripts do not detect that the embedded script
        # has changed, so we must start over.
        # TODO: regenerate only the embedded image to speed up builds.
        make clean; rm -rf bin

        extra_cflags="$( get_extra_flags $device $version )"

        # The generated ROM file is the device name.
        make -j ${procs} bin/${device} \
            EXTRA_CFLAGS="${extra_cflags}" \
            DEBUG=${debug} \
            TRUST=${certs} \
            EMBED=${stage1}

        # Copy it to a structured location.
        # Note: the update image depends on this structure to locate an image.
        mkdir -p ${rom_output_dir}/${device}/${version}
        cp bin/${device} ${rom_output_dir}/${device}/${version}/${hostname}.mrom
      done
    popd
  done
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

# Embedded ROM image.
# VERSION=3.4.800

prepare_flexboot_source \
    ${BUILD_DIR} \
    ${CONFIG_DIR} \
    $SCRIPTDIR/vendor/flexboot-20160705.tar.gz \
    flexboot

generate_stage1_ipxe_scripts \
    ${BUILD_DIR} \
    ${CONFIG_DIR} \
    "${HOSTNAMES}" \
    ${BUILD_DIR}/stage1_scripts

build_roms \
    ${BUILD_DIR}/flexboot/src \
    ${BUILD_DIR}/stage1_scripts \
    "${VERSION}" \
    "${DEBUG}" \
    "${CERTS}" \
    ${BUILD_DIR}/mellanox-roms