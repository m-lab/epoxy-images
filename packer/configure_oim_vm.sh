#!/bin/bash
#
# This script gets uploaded and executed on the temporary VM that Packer
# creates when generating custom images. It should do everything necessary to
# prepare the custom image's environment for VMs in the Google-internal GCP
# project hosted by the OIM team.

set -euxo pipefail

# Don't let apt prompt for anything, since there is no one to answer.
export DEBIAN_FRONTEND=noninteractive

# Update the apt package index, bring every package in the base image
# (including the kernel) up to date, and install any needed packages.
apt update
apt full-upgrade --yes
apt install --yes \
  ca-certificates \
  curl

# Install Docker. apt-key no longer exists in recent Ubuntu releases, so the
# repository signing key goes in a keyring file referenced by the source entry.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
source /etc/os-release
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt update
apt install --yes docker-ce docker-compose-plugin

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
