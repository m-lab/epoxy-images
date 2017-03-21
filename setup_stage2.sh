#!/bin/bash
#
# Builds a stage2 ePoxy image, including all binary dependencies for a minimal
# initramfs and stand-alone kernel.

# Report all commands.
set -x

# Exit on any error.
set -e

# Define positional parameters.
BUILD_DIR=${1:?Error: Please specify output directory for all build artifacts}
VENDOR_DIR=${2:?Error: Please specify path to vendor package directory}
CONFIG_DIR=${3:?Error: Please specify path to configuration directory}
INITRAM_NAME=${4:?Error: Please specify path of initramfs output file}
KERNEL_NAME=${5:?Error: Please specify path to vmlinuz output file}


# Get canonical paths for each argument.
BUILD_DIR=$( readlink --canonicalize $BUILD_DIR )
VENDOR_DIR=$( readlink --canonicalize $VENDOR_DIR )
CONFIG_DIR=$( readlink --canonicalize $CONFIG_DIR )
INITRAM_NAME=$( readlink --canonicalize-missing $INITRAM_NAME )
KERNEL_NAME=$( readlink --canonicalize-missing $KERNEL_NAME )


# Setup environmental and derived values.
INITRAMFS_DIR=$BUILD_DIR/initramfs_$( basename ${CONFIG_DIR} )
ARCH=$( arch | sed -e 's/i686/i386/' )


# Unpacks a tar archive at the named directory. If the directory already
# exists, no action is taken.
#
# Arguments:
#   dirname: name of directory in $PWD.
#   tgz: absolute path to a tar archive.
function unpack () {
  local dirname=$1
  local tgz=$2
  if ! test -d $dirname ; then
    if ! test -f $tgz ; then
      echo "Error: no such file: $tgz" 1>&2
      exit 1
    fi
    tar xf $tgz
  fi
}


# Builds busybox using a predefined configuration.
#
# Arguments:
#   build: absolute path to a build directory.
#   vendor: absolute path to a vendor directory with tar archives.
#   config: absolute path to a configuration directory.
function build_busybox() {
  local busybox_version=$1
  local build=$2
  local vendor=$3
  local config=$4

  if ! test -f $build/local/bin/busybox ; then
    pushd $build
      unpack ${busybox_version} $vendor/${busybox_version}.tar.bz2
      pushd ${busybox_version}
        # Copy busybox configuration, updating the install directory.
        sed -e "s|BUSYBOX_INSTALL_DIR|$build/local|g" \
                $config/busybox_config > .config
        make all
        make install
      popd
    popd
  fi
}


# Builds static versions of the dropbear ssh server and client binaries.
#
# Arguments:
#   build: absolute path to a build directory.
#   vendor: absolute path to a vendor directory with tar archives.
#   config: absolute path to a configuration directory.
function build_dropbear() {
  local dropbear_version=$1
  local build=$2
  local vendor=$3
  local config=$4

  if ! test -f $build/local/sbin/dropbear ; then
    pushd $build
      unpack ${dropbear_version} $vendor/${dropbear_version}.tar.bz2
      pushd ${dropbear_version}
        STATIC=1 ./configure --prefix=$build/local

        # The MULTI=1 option creates a single binary named "dropbearmulti"
        # that contains the logic for all of the named PROGRAMS. On
        # installation, use symlinks to name and invoke the dropbearmulti
        # binary as an individual program.
        make PROGRAMS="dropbear dropbearkey dbclient scp" \
            MULTI=1 STATIC=1 SCPPROGRESS=1
        make PROGRAMS="dropbear dropbearkey dbclient scp" \
            MULTI=1 STATIC=1 SCPPROGRESS=1 install

      popd
    popd
  fi
}


# Builds kexec as a static binary.
#
# Arguments:
#   build: absolute path to a build directory.
#   vendor: absolute path to a vendor directory with tar archives.
#   config: absolute path to a configuration directory.
function build_kexec() {
  local kexec_version=$1
  local build=$2
  local vendor=$3
  local config=$4

  if ! test -f $build/local/sbin/kexec ; then
    pushd $build
      unpack ${kexec_version} $vendor/${kexec_version}.tar.xz
      pushd ${kexec_version}
        LDFLAGS=-static ./configure --prefix $build/local
        make
        make install
      popd
    popd
  fi
}


# Builds rngd as a static binary.
#
# Arguments:
#   build: absolute path to a build directory.
#   vendor: absolute path to a vendor directory with tar archives.
#   config: absolute path to a configuration directory.
function build_rngd() {
  local rngd_version=$1
  local build=$2
  local vendor=$3
  local config=$4

  if ! test -f $build/local/sbin/rngd ; then
    pushd $build
      unpack ${rngd_version} $vendor/${rngd_version}.tar.gz
      pushd ${rngd_version}
        LDFLAGS=-static ./configure --prefix=$build/local
        make
        make install
      popd
    popd
  fi
}


# Builds haveged as a static binary.
#
# Arguments:
#   build: absolute path to a build directory.
#   vendor: absolute path to a vendor directory with tar archives.
#   config: absolute path to a configuration directory.
function build_haveged() {
  local haveged_version=$1
  local build=$2
  local vendor=$3
  local config=$4

  if ! test -f $build/local/sbin/haveged ; then
    pushd $build
      unpack ${haveged_version} $vendor/${haveged_version}.tar.gz
      pushd ${haveged_version}
        ./configure --prefix=$build/local --enable-static LDFLAGS=-static
        make
        pushd src
          # TODO(soltesz): do this automatically.
          # Manually generate a static binary, since configure doesn't do this
          # for us.
          gcc -static -Wall -I.. -g -O2 -o haveged haveged.o ./.libs/libhavege.a
        popd
        make install
      popd
    popd
  fi
}


# TODO(soltesz): build epoxyclient.
function build_epoxyclient() {
  echo "TODO: build epoxyclient"
}


# Compresses binaries using upx, the "Ultimate Packer or eXecutables."
#
# Arguments:
#   install_prefix: absolute path that prefixes all given file names.
#   relative_paths...: additional positional parameters for the relative paths
#       of binaries to compress. Paths should be relative to the install_prefix.
function compress_binaries() {
  local install_prefix=$1
  shift

  echo "Compressing binaries"
  mkdir -p $install_prefix/upx

  while [[ $# -gt 0 ]] ; do
    file=$install_prefix/$1
    name=$(basename $file)
    # Compress if upx file is missing, or if the source binary is newer.
    if ! test -f $install_prefix/upx/$name || \
        test $file -nt $install_prefix/upx/$name ; then
      upx -f --brute -o$install_prefix/upx/$name $file
    fi

    shift
  done
}


# Creates an initramfs.
#
# Globals:
#   ARCH: the processor architecture, i.e. i386 or x86_64.
# Arguments:
#   build: absolute path to a build directory.
#   vendor: absolute path to a vendor directory with tar archives.
#   initramfs: absolute path to a directory to create the initramfs.
function setup_initramfs() {
  local build=$1
  local config=$2
  local initramfs=$3

  echo "Setting up root filesystem.."
  # Recreate the initramfs to start from a clean slate.
  rm -rf $initramfs && mkdir $initramfs

  pushd $initramfs
    # Create top level directories.
    for dir in bin sbin usr/bin usr/sbin proc sys dev/pts \
        etc/ssl etc/dropbear lib/${ARCH}-linux-gnu lib64 \
        var/run var/log root/.ssh newroot ; do
      mkdir -p $dir
    done

    # Restrict permissions on the root home directory.
    chmod 700 root

    # Setup devices for the kernel console and first tty.
    # These should be present in the filesystem before init runs during boot.
    mknod -m 622 dev/console c 5 1
    mknod -m 622 dev/tty0 c 4 0

    ##
    # Install binaries.
    cp $build/local/upx/busybox       bin
    cp $build/local/upx/dropbearmulti bin
    cp $build/local/upx/kexec         sbin

    # Help generate more entropy for /dev/random.
    cp $build/local/upx/rngd          sbin
    cp $build/local/upx/haveged       sbin

    # TODO(soltesz): install epoxyclient
    # cp $build/local/upx/epoxyclient   bin

    ##
    # Install libraries.

    # libnss is the Name Service Switch. It is responsible for service name
    # lookup via DNS, /etc/hosts, or other mechanisms. We must copy the system
    # libraries because there is no static library for libnss.
    cp /etc/nsswitch.conf                    etc
    cp /lib/${ARCH}-linux-gnu/libc.so.6      lib/${ARCH}-linux-gnu
    cp /lib/${ARCH}-linux-gnu/libresolv.so.2 lib/${ARCH}-linux-gnu
    cp /lib/${ARCH}-linux-gnu/libnss*        lib/${ARCH}-linux-gnu
    cp /lib/${ARCH}-linux-gnu/libnsl*        lib/${ARCH}-linux-gnu

    # Strace and dependencies. Helpful to debug issues in a stage2 environment.
    # TODO(soltesz): remove strace and dependencies.
    cp /usr/bin/strace                       usr/bin
    cp /lib/ld-linux.so.2                    lib || :
    cp /lib64/ld-linux-x86-64.so.2           lib64 || :
    ln -s /lib64/ld-linux-x86-64.so.2        lib || :

    ##
    # Install configuration.

    # SSL root certificates.
    # Note: if ePoxy is running in Google AppEngine, then system wide SSL
    # certificates are sufficient. If ePoxy is running in stand-alone mode,
    # then we must also include the private ePoxy root CA.
    cp -L -r /etc/ssl/certs           etc/ssl

    # SSH authorized keys.
    cp $config/authorized_keys        root/.ssh/authorized_keys

    # Busybox can setup all symlinks at run time. However, we add the first
    # symlink to bin/sh so /init can run as a shell script.
    ln -s /bin/busybox          bin/sh

    # All ssh targets.
    ln -s /bin/dropbearmulti    bin/scp
    ln -s /bin/dropbearmulti    bin/dropbearkey
    ln -s /bin/dropbearmulti    sbin/dropbear

    # An empty config is sufficient to keep busybox mdev happy.
    touch etc/mdev.conf

    # Add the root user and group.
    echo "root:UEgHv/R7qZCmQ:0:0:Linux,,,:/root:/bin/sh" > etc/passwd
    echo "root:*:0:root" > etc/group
    echo 'export PATH=$PATH:/sbin:/usr/sbin' > root/.profile
    echo 'set -o vi' >> root/.profile

    # Remaining startup configuration.
    cp $config/init        ./
    cp $config/inittab     etc
    cp $config/rc.local    etc
    cp $config/resolv.conf etc
  popd

  # Force ownership to root for all files in the initramfs.
  chown -R root:root $initramfs
}


# Generates an initramfs cpio file from a pre-created filesystem layout.
#
# Arguments:
#   initramfs: absolute path to an initramfs directory.
#   output: absolute path to a filename to write a gzip compressed cpio file.
function write_initramfs() {
  local initramfs=$1
  local output=$2

  # Guarantee that all directories exist in output path.
  mkdir -p $( dirname "${output}" )
  pushd $initramfs
    find . | cpio -H newc -o | gzip -c > "${output}"
  popd
}


# Builds a stand alone kernel.
#
# Arguments:
#   build: absolute path to a build directory.
#   config: absolute path to a configuration directory.
#   initramfs_dir: absolute path to an initramfs directory.
#   initramfs: absolute path to a cpio file.
#   kernel: absolute path to a filename to write the kernel image.
function build_kernel() {
  local build=$1
  local config=$2
  local initram_dir=$3
  local initramfs=$4
  local kernel=$5

  # Extract the linux source version.
  local linux_source_version=$(
      dpkg-query --show --showformat='${Depends}\n' linux-source )
  if test -z "${linux_source_version}" || \
      ! test -f /usr/src/${linux_source_version}.tar.bz2 ; then
      echo "Error: failed to find linux source from linux-source package" 1>&2
      exit 1
  fi

  pushd $build
    unpack ${linux_source_version} /usr/src/${linux_source_version}.tar.bz2
    pushd ${linux_source_version}
      if test "${initramfs}" -nt "${kernel}" ; then
        # Remove build artifacts to force re-generation.
        rm -f arch/x86/boot/bzImage
        rm -f usr/initramfs_data.cpio.gz

        # Check if the config file has changed.
        local tmpcfg=$( mktemp /tmp/kernel.config-XXXXXX )
        sed -e "s|INITRAMFS_SOURCE_DIR|$initram_dir|g" \
            $config/linux_config_minimal > "${tmpcfg}"

        # If the config files differ replace with the new temp config file.
        if ! diff "${tmpcfg}" .config ; then
          cp "${tmpcfg}" .config
        fi

        # Apparently, a patch still missing from default ubuntu kernel source.
        # https://patchwork.kernel.org/patch/9234191/
        # Build fails without this patch.
        patch --forward -p1 < $config/spinlock.patch || :

        # Update our config with any new config options, using their default
        # values. Periodically, we will need to merge these into our
        # linux_config_minimal.
        make olddefconfig

        # Build the compressed kernel image.
        make -j3 bzImage

        # Copy to output name.
        cp arch/x86/boot/bzImage "${kernel}"
      fi
    popd
  popd
}


function main() {

  # Make build directory if it does not already exist.
  mkdir -p $BUILD_DIR

  build_busybox busybox-1.25.0 $BUILD_DIR $VENDOR_DIR $CONFIG_DIR
  build_dropbear dropbear-2016.74 $BUILD_DIR $VENDOR_DIR $CONFIG_DIR
  build_kexec kexec-tools-2.0.13 $BUILD_DIR $VENDOR_DIR $CONFIG_DIR
  build_rngd rng-tools-5 $BUILD_DIR $VENDOR_DIR $CONFIG_DIR
  build_haveged haveged-1.9.1 $BUILD_DIR $VENDOR_DIR $CONFIG_DIR
  build_epoxyclient $BUILD_DIR $VENDOR_DIR $CONFIG_DIR

  compress_binaries $BUILD_DIR/local \
      bin/busybox \
      bin/dropbearmulti \
      sbin/kexec \
      sbin/haveged \
      sbin/rngd

  setup_initramfs $BUILD_DIR $CONFIG_DIR $INITRAMFS_DIR
  write_initramfs $INITRAMFS_DIR $INITRAM_NAME

  build_kernel $BUILD_DIR $CONFIG_DIR $INITRAMFS_DIR $INITRAM_NAME $KERNEL_NAME
}

main
