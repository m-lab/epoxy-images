#!/bin/bash

# Create a tar-gzipped file that contains all the necessary files and scripts
# necessary to build custom images for virtual machines. Doing this means we
# don't have to remember which files need uploading and and moving around on the
# remote side. Instead, any files in configs/stage3_ubuntu_virtual are packaged
# up, pushed to the VM that Packer uses to create the custom image, and them
# splatted into the filesystem in all the right places. We pass the -h flag to
# tar to dereference any symlinks, since a good number of the files in
# configs/stage3_ubuntu_virtual are symlinks to their counterparts in configs/stage3_ubuntu.
tar -hczf packer/virtual-files.tar.gz --owner root --group root -C configs/stage3_ubuntu_virtual .

cd packer
packer init .
packer build -force \
  -var "project_id=$PROJECT" \
  -var "image_version=$IMAGES_VERSION" \
  mlab.pkr.hcl
