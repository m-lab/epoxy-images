#!/bin/bash
#
# This script gets uploaded and executed on the temporary VM that Packer
# creates when generating custom images. It should do everything necessary to
# prepare the custom image's environment for VMs in the Google-internal GCP
# project hosted by the OIM team.

set -euxo pipefail

METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

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

# Make an M-Lab bin directory
mkdir -p /opt/mlab/bin/

# Copy necessary files to correct locations
cp /tmp/virtual_google_oim/docker-compose.yml /home/mlab/
cp /tmp/virtual_google_oim/launch-byos.sh /opt/mlab/bin/
cp /tmp/virtual_google_oim/launch-byos.service /etc/systemd/system/

# Enable launch-byos.service
systemctl daemon-reload
systemctl enable launch-byos.service
