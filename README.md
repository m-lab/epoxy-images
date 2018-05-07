| Branch | Status |
|--------|--------|
| master | [![Build Status](https://travis-ci.org/m-lab/epoxy-images.svg?branch=master)](https://travis-ci.org/m-lab/epoxy-images) |
| dev | [![Build Status](https://travis-ci.org/m-lab/epoxy-images.svg?branch=dev)](https://travis-ci.org/m-lab/epoxy-images) |

# epoxy-images

Support for building Linux kernels, rootfs images, and ROMs for ePoxy

An ePoxy managed system depends on several image types:

 * stage1 images that are either flashed to NICs, or burned to CDs.
 * stage2 Linux images that provide a minimal network boot environment.
 * stage3 Linux ROM update images, that (re)flash iPXE ROMs to NICs.

# Building images

## Building stage1 iPXE ROMs

TODO(soltesz): add notes for building iPXE ROMs.

## Building stage2 Linux images

The ePoxy stage2 image is a single file. It is a Linux kernel with embedded
initramfs.

The `setup_stage2.sh` script creates an initramfs filesystem, a cpio version of
the initramfs, and the kernel with embedded initramfs.

    docker build -t epoxy-images-builder  .
    docker run -v $PWD:/images -it epoxy-images-builder \
        /images/setup_stage2.sh /buildtmp /images/vendor \
            /images/configs/stage2 \
            /images/output/stage2_initramfs.cpio.gz \
            /images/output/stage2_vmlinuz

    docker run -v $PWD:/images -it epoxy-images-builder \
        /images/simpleiso /images/output/stage2_vmlinuz \
            /images/output/stage2.iso

Using this ISO, you should be able to boot the image using VirtualBox or a
similar tool. If your ssh key is in `configs/stage2/authorized_keys`, and the VM
is configured to attach to a Host-only network on the 192.168.0.0/24 subnet,
then you can ssh to the machine at:

    ssh root@192.168.0.2

Alternate network configurations are also possible, using the same format as the
[nsfroot][nfsroot] `ip=` kernel parameter. The default value is shown below.

    network=192.168.0.2::192.168.0.1:255.255.255.0:default-net:eth0::8.8.8.8:
    docker run -v $PWD:/images -it epoxy-images-builder \
        /images/simpleiso -x epoxy.ip=${network} \
            /images/output/stage2_vmlinuz \
            /images/output/stage2.iso

[nfsroot]: https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt

## Building stage3 Linux ROM update images

TODO(soltesz): add notes for building Linux ROM update images.

# Deploying images

TODO(soltesz): outline how ePoxy images are deployed to GCS.
