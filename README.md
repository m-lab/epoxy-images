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

# Upgrading Kubernetes components

Upgrading Kubernetes components on platform nodes is a separate process from
[upgrading them in the API
cluster](https://github.com/m-lab/k8s-support/#upgrading-the-api-cluster).
Upgrading Kubernetes on platform nodes should _always_ occur _after_ the API
cluster has been upgraded for a given project. The script
./setup\_stage3\_ubuntu.sh has logic which is designed to enforce this
requirement, but it is still worth mentioning here.

Upgrading Kubernetes components on platform nodes should be as simple as
copying the values for the [identially named config
variables](https://github.com/m-lab/k8s-support/blob/master/manage-cluster/k8s_deploy.conf#L31)
from the k8s-support repository to the ones in ./config.sh in this repository:

* K8S\_VERSION
* K8S\_CNI\_VERSION
* K8S\_CRICTL\_VERSION

Once the version strings are updated, and match those in the k8s-support
repository, just follow the usual deployment path for epoxy-images i.e., push
to sandbox, create PR, merge to master, tag repository. The Cloud Builds for
this repository will generate new boot images with the updated Kubernetes
components. In mlab-sandbox and mlab-staging, the newly built images will be
automatically deployed to a node upon reboot. However, in production (mlab-oti)
they will not be automatically deployed without further action.

In order to deploy the new boot images to production you will need modify the
`ImagesVersion` property of every ePoxy Host GCD entity to match the tag name
of the production release for this repository. This can be done using the
`epoxy_admin` tool. If you don't already have it installed, then install it
with:

```
$ go get github.com/m-lab/epoxy/cmd/epoxy_admin
```

Once installed, you can update the ePoxy Host GCD entities in the mlab-oti
project with a command like the following. **NOTE**: do not run this command
against the mlab-sandbox or mlab-staging projects, as `ImagesVersion` is a
static value in those projects and should always be "latest":

```
$ epoxy_admin update --project mlab-oti --images-version <tag> --hostname "^mlab[1-3]"
```

None of the nodes in any project will be running the updated images until they
are rebooted. You can trigger a rolling reboot of all nodes in a cluster with a
small shell command like the following:

```
$ for node in $(kubectl --context <project> get nodes | grep '^mlab[1-4]' | awk '{print $1}'); do \
    ssh $node 'sudo touch /var/run/mlab-reboot'; \
  done
```

The former command assumes you have ssh access to every platform node. It
leverages the [Kured
DaemonSet](https://github.com/m-lab/k8s-support/blob/master/k8s/daemonsets/core/kured.jsonnet)
running on the platform by creating the "reboot sentinel" file
(/var/run/mlab-reboot) on every node, which tells Kured that a reboot is
required. From there, Kured handles rebooting all flagged nodes in a safe way
(one node a time).

You can check the progress and/or completion of the upgrade by looking at the
kubelet version for a node as reported by kubectl:

```
$ kubectl --context <project> get nodes
```

