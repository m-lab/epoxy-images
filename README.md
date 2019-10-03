| Branch | Status |
|--------|--------|
| master | [![Build Status](https://travis-ci.org/m-lab/epoxy-images.svg?branch=master)](https://travis-ci.org/m-lab/epoxy-images) |

# epoxy-images

Support for building Linux kernels, rootfs images, and ROMs for ePoxy

An ePoxy managed system depends on several image types:

 * generic Linux images that provide a minimal network boot environment.
 * stage1 images that embed node network configuration and are either flashed
   to NICs, or burned to CDs.
 * stage3 Linux ROM update images, that (re)flash iPXE ROMs to NICs.

# Build Automation

The epoxy-images repo is connected to Google Cloud Build.

* mlab-sandbox - push to a branch matching `sandbox-*` builds cloudbuild.yaml &
  cloudbuild-stage1.yaml.
* mlab-staging - push to `master` builds both cloudbuild.yaml and
  cloudbuild-stage1.yaml
* mlab-oti - tags matching `v[0-9]+.[0-9]+.[0-9]+` builds cloudbuild.yaml &
  cloudbuild-stage1.yaml

# Building images

See cloudbuild-stage1.yaml for current steps for stage1 images.

You can also run the build locally using `docker`.

```sh
docker build -t epoxy-images-builder  .

docker run --privileged -e PROJECT=mlab-sandbox -e ARTIFACTS=/workspace/output \
  -v $PWD:/workspace -it epoxy-images-builder /workspace/builder.sh stage1_minimal

docker run --privileged -e PROJECT=mlab-sandbox -e ARTIFACTS=/workspace/output \
  -v $PWD:/workspace -it epoxy-images-builder /workspace/builder.sh stage1_mlxrom

docker run --privileged -e PROJECT=mlab-sandbox -e ARTIFACTS=/workspace/output \
  -v $PWD:/workspace -it epoxy-images-builder /workspace/builder.sh stage1_isos
```

Using an ISO, you should be able to boot the image using VirtualBox or a
similar tool. If your ssh key is in `configs/stage2/authorized_keys`, and the VM
is configured to attach to a Host-only network on the 192.168.0.0/24 subnet,
then you can ssh to the machine at:

```sh
ssh root@192.168.0.2
```

# Deploying images

The M-Lab deployment of the ePoxy server reads images from GCS. The cloudbuild
steps deploy images to similarly named folders:

* `output/stage1_mlxrom/*` -> `gs://epoxy-mlab-sandbox/stage1_mlxrom/`
* `output/stage1_isos/*` -> `gs://epoxy-mlab-sandbox/stage1_isos/`

## BIOS & UEFI Support

The `simpleiso` command creates ISO images that are capable of booting from
either BIOS or UEFI systems. BIOS systems use isolinux while UEFI systems use
grub. These images should also work with USB media.

### Testing USB images

VirtualBox natively supports boot from ISO images & supports BIOS or UEFI
boot environments. To support VM boot from USB images we must create a
virtualbox disk image from the raw USB disk image.

```bash
VBoxManage convertdd boot.fat16.gpt.img boot.vdi --format VDI
```

Then select that image in the VM configuration.
