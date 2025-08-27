#!/bin/bash
#
# This script gets uploaded and executed on the temporary VM that Packer
# creates when generating custom images. It should do everything necessary to
# prepare the custom image's environment for VMs in the Google-internal GCP
# project hosted by the OIM team.

set -euxo pipefail

# Update the apt package index and install any needed packages.
apt update
apt install --yes \
  apt-transport-https \
  ca-certificates \
  curl \
  software-properties-common

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu `lsb_release -cs` stable"
apt update
apt install --yes docker-ce

# Make sure that the BBR kernel module gets loaded on boot
echo "tcp_bbr" >> /etc/modules

# Add an M-Lab user, and add it to the docker group
adduser mlab --gecos "M-Lab User" --disabled-login
adduser mlab docker

# Copy the Autojoin API key into a file in mlab's home directory
echo "${API_KEY}" > /home/mlab/api_key

# Make an M-Lab dirs in /opt
mkdir -p /opt/mlab/bin/
mkdir -p /opt/mlab/conf/

# Copy necessary files to correct locations
cp /tmp/virtual_google_oim/launch-autonode.sh /opt/mlab/bin/
cp /tmp/virtual_google_oim/launch-autonode.service /etc/systemd/system/
cp /tmp/virtual_google_oim/env.template /opt/mlab/conf/

# Enable launch-autonode.service
systemctl daemon-reload
systemctl enable launch-autonode.service
