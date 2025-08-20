#!/bin/bash

version=$(date --utc +%Ft%H-%M-%S)

export PATH=$PATH:/google-cloud-sdk/bin

cd packer
packer init .
packer build -force \
  -var "gcp_project=$PROJECT" \
  -var "version=$version" \
  -var "api_key=$GOOGLE_OIM_AUTOJOIN_API_KEY" \
  google-oim.pkr.hcl
