#!/bin/bash
#
# A script to create ePoxy images manually.

# Edit the following variable to suit your needs, most importantly PROJECT and NODE_REGEXP.
COREOS_VERSION="2135.6.0"
PROJECT="mlab-staging"
NODE_REGEXP="mlab4.(bru02|lax02|syd02)"
GCS_BUCKET="gs://epoxy-${PROJECT}"
GSUTIL_HEADER="Cache-Control:private, max-age=0, no-transform"

# Install Docker.
apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
apt-get update
apt-get install -y docker-ce

# Clone the epoxy-images repository.
git clone --recurse-submodules https://github.com/m-lab/epoxy-images.git
cd epoxy-images

# Install Google Cloud SDK
travis/install_gcloud.sh

# Make the output directory, removing any existing one first.
rm -rf output
mkdir output

# Create the epoxy-images Docker image.
docker build -t epoxy-images-builder . &> build.log

# Build images.

docker run -t -v ${PWD}:/images epoxy-images-builder \
  bash -c "/images/setup_stage2.sh   \
  /buildtmp \
  /images/vendor \
  /images/configs/stage2 \
  /images/output/stage2_initramfs.cpio.gz \
  /images/output/stage2_vmlinuz \
  /images/output/epoxy_client /images/stage2.log \
  /images/travis/one_line_per_minute.awk"

docker run -v ${PWD}:/images -w /images epoxy-images-builder \
  bash -c "umask 0022; /images/setup_stage3_coreos.sh /images/configs/stage3_coreos \
  /images/output/epoxy_client \
  http://stable.release.core-os.net/amd64-usr/${COREOS_VERSION}/coreos_production_pxe.vmlinuz \
  http://stable.release.core-os.net/amd64-usr/${COREOS_VERSION}/coreos_production_pxe_image.cpio.gz \
  /images/output/coreos_custom_pxe_image.cpio.gz &> /images/coreos.log"

gsutil cp gs://vendor-mlab-oti/epoxy-images/mft-4.4.0-44.tgz ${PWD}

docker run -it --privileged -v ${PWD}:/images -w /images epoxy-images-builder \
  bash -c "umask 0022; install -D -m 644 /images/mft-4.4.0-44.tgz /build/mft-4.4.0-44.tgz \
    && echo 'Starting stage3_update build' \
    && /images/setup_stage3_update.sh \
        /build /images/output /images/configs/stage3_update \
        /images/output/epoxy_client \
      &> /images/stage3_update.log \
    && echo 'Starting ROM & ISO build' \
    && /images/setup_stage3_update_isos.sh \
      ${PROJECT} /build /images/output '${NODE_REGEXP}.*' 3.4.809 \
        /images/stage3_update_iso.log /images/travis/one_line_per_minute.awk"

# Copy all artifacts to GCS.

gsutil -h "${GSUTIL_HEADER}" cp -r \
  ${PWD}/output/stage2_vmlinuz \
  ${PWD}/output/coreos_custom_pxe_image.cpio.gz \
  ${PWD}/output/coreos_production_pxe.vmlinuz \
  ${PWD}/actions/stage2/stage1to2.ipxe \
  ${PWD}/actions/stage3_coreos/*.json \
  ${GCS_BUCKET}/stage3_coreos/

gsutil -h "${GSUTIL_HEADER}" cp -r \
  ${PWD}/output/stage2_vmlinuz \
  ${PWD}/output/vmlinuz_stage3_update \
  ${PWD}/output/initramfs_stage3_update.cpio.gz \
  ${PWD}/actions/stage2/stage1to2.ipxe \
  ${PWD}/actions/stage3_update/*.json \
  ${GCS_BUCKET}/stage3_update/

gsutil -h "${GSUTIL_HEADER}" cp -r \
  ${PWD}/output/*.iso \
  ${GCS_BUCKET}/stage3_update_iso/

gsutil -h "${GSUTIL_HEADER}" cp -r \
  ${PWD}/output/stage1_mlxrom/* \
  ${GCS_BUCKET}/stage1_mlxrom/

gsutil -h "${GSUTIL_HEADER}" cp -r \
  ${PWD}/output/stage1_mlxrom/*/* \
  ${GCS_BUCKET}/stage1_mlxrom/latest/
