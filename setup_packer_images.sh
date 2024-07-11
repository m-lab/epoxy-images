#!/bin/bash

# Create a tar-gzipped file that contains all the necessary files and scripts
# necessary to build custom images for virtual machines. Doing this means we
# don't have to remember which files need uploading and moving around on the
# remote side. Instead, any files in configs/virtual_ubuntu are packaged
# up, pushed to the VM that Packer uses to create the custom image, and them
# splatted into the filesystem in all the right places. We pass the
# --dereference flag to tar to dereference any symlinks, since a good number of
# the files in configs/virtual_ubuntu are symlinks to their counterparts in
# configs/stage3_ubuntu.
tar --dereference -czf packer/virtual-files.tar.gz --owner root --group root -C configs/virtual_ubuntu .

# In mlab-sandbox and mlab-staging, $IMAGES_VERSION will always be "latest",
# which is right for physical machine images but does not work for virtual
# machine images. Terraform does not apparently distinguish between disk images
# that have the same name in the cloud provider that have actually changed. For
# example, let's say that you have an image  named "my-image-latest". You
# then make some changes to the image in this repository and a new image is
# created and uploaded to the cloud provider with the same name. When you run
# "terraform plan" it does not recognize that the object with the same name has
# actually changed. Using a date string for the version allows us to test new
# images by forcing us to change the name of the image in the terraform configs.
# For mlab-oti, $IMAGES_VERSION will be the repository tag, which is fine, since
# then virtual image names match the version for physical machines.
#
# Changing dots to dashes in $IMAGES_VERSION and the somewhat awkward date
# string are due to restrictions in GCP resource names:
# https://cloud.google.com/compute/docs/naming-resources
if [[ $PROJECT != "mlab-oti" ]]; then
  version=$(date --utc +%Ft%H-%M-%S)
else
  version=${IMAGES_VERSION//./-}
fi

export PATH=$PATH:/google-cloud-sdk/bin
export PACKER_LOG=1

cd packer
packer init .
packer build -force -debug \
  -var "gcp_project=$PROJECT" \
  -var "image_version=$version" \
  mlab.pkr.hcl
