#!/bin/bash

version=$(date --utc +%Ft%H-%M-%S)

export PATH=$PATH:/google-cloud-sdk/bin

cd packer
packer init .
# Build the image, retrying across candidate zones when one is out of capacity.
# See packer/zone_fallback.sh.
# shellcheck source=packer/zone_fallback.sh
source ./zone_fallback.sh
packer_build_with_zone_fallback google-oim.pkr.hcl \
  -var "gcp_project=$PROJECT" \
  -var "version=$version" \
  -var "api_key=$GOOGLE_OIM_AUTOJOIN_API_KEY"
