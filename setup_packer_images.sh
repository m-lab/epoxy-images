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

cd packer
packer init .
packer build -force \
  -var "gcp_project=$PROJECT" \
  -var "image_version=$IMAGES_VERSION" \
  mlab.pkr.hcl
