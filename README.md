| Branch | Status |
|--------|--------|
| master | [![Build Status](https://travis-ci.org/m-lab/epoxy-images.svg?branch=master)](https://travis-ci.org/m-lab/epoxy-images) |

# Boot Images for ePoxy Server

This repo supports building Linux kernels, rootfs images, and ROMs for ePoxy
boot API.

An ePoxy managed system depends on several image types:

* stage1 images are either flashed to NICs or burned to CDs. These don't
  change very often once installed.
* stage2 Linux images provide a minimal, consistent network boot environment.
* stage3 Linux images provide a complete environment, e.g. to flash the
  iPXE ROMs to NICs, or run CoreOS or another distro.

# Initial Setup

Once built, by default images are deployed to a GCS bucket for the current
project, `gs://epoxy-<project>`. Here `<project>` corresponds to the GCP
project name.

When creating a new bucket, set the default ACL to `public-read` so that
booting nodes can download the files without authentication.

```sh
gsutil defacl set public-read gs://epoxy-mlab-sandbox
```

# Building Images

Image builds are performed by Google Cloud Build using the `cloudbuild.yaml`
configuration.

The first build step is to create a custom docker container that serves as a
build environment for all subsequent steps.

The environment variables for each build step are particular to the needs of the
M-Lab projects. Update them for your own build.

## Building Images for Development

Before building with cloudbuild.yaml, it may be helpful to build locally. To
build images locally, use the same steps as found in cloudbuild.yaml, for
example:

```sh
docker build -t epoxy-images-builder .
docker run -e PROJECT=$PROJECT_ID -e ARTIFACTS=/workspace/output \
  -it epoxy-images-builder /workspace/builder.sh stage1_minimal
```

Most builds generate two files, the Linux kernel and corresponding initramfs.
In the case of the stage1_minimal target, the build generates:

```txt
$ ls -l output/
-rw-r--r-- 1 root root 158861392 May 13 16:43 initramfs_stage1_minimal.cpio.gz
-rw-r--r-- 1 root root   7013968 May 13 16:43 vmlinuz_stage1_minimal
```

The initramfs is large because it contains the complete "minimal" root
filesystem, including kernel modules, binaries and all associated libraries.

Using these base images it's possible to create an ISO or USB image for
booting with VirtualBox. Alternate network configurations are also possible
by modifying the kernel parameters below:

```bash
kargs="net.ifnames=0 autoconf=0 "
kargs+="epoxy.interface=eth0 "
kargs+="epoxy.ipv4=192.168.0.2/24,192.168.0.1,8.8.8.8,8.8.4.4 "
kargs+="epoxy.ipv6= "
kargs+="epoxy.hostname=localhost "

docker run -v $PWD:/workspace -it epoxy-images-builder \
  /workspace/simpleiso -x "${kargs}" \
    -i /workspace/output/initramfs_stage1_minimal.cpio.gz \
    /workspace/output/vmlinuz_stage1_minimal \
    /workspace/output/stage1_minimal.iso
```

You should be able to boot the ISO image using VirtualBox or any machine.
If the VM is configured to attach to a Host-only network on the 192.168.0.0/24
subnet, then you can ssh to the machine at:

```sh
ssh root@192.168.0.2
```

# BIOS & UEFI Support

The `simpleiso` command creates ISO images that are capable of booting from
either BIOS or UEFI systems. BIOS systems use isolinux while UEFI systems use
grub.

The `simpleusb` command only creates fat16.gpt images capable of booting from
UEFI systems. While hybrid boot for GPT & MBR may be possible, tools that
support it warn "Hybrid MBRs are flaky and dangerous!", so `simpleusb` only
support UEFI systems.

## Testing USB images

VirtualBox natively supports boot from ISO images & supports BIOS or UEFI
boot environments. To support VM boot from USB images we must create a
virtualbox disk image from the raw USB disk image.

```bash
VBoxManage convertdd boot.fat16.gpt.img boot.vdi --format VDI
```

Then select that image in the VM configuration.
