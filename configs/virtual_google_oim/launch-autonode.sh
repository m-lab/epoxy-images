#!/bin/bash

set -euxo pipefail

METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

# Collect various bits of metadata necessary to populate the Docker Compose
# environment file.
IPV4=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/network-interfaces/0/forwarded-ips/0")
IPV6=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/network-interfaces/0/forwarded-ipv6s/0")
PROBABILITY=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/attributes/probability")
IATA=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/attributes/probability")
AUTONODE_VERSION=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/attributes/autonode-version")

# Fetch the correct version of the Docker Compose file
curl --silent "https://raw.githubusercontent.com/m-lab/autonode/refs/tags/${AUTONODE_VERSION}/docker-compose.yml"

# Evaluate the Docker Compose env file
sed -e "s|{{API_KEY}}|$API_KEY|" \
    -e "s|{{IATA}}|$IATA|" \
    -e "s|{{PROBABILITY}}|$PROBABILITY|" \
    -e "s|{{IPV4}}|$IPV4|" \
    -e "s|{{IPV6}}|$IPV6|" \
    /tmp/virtual_google_oim/env.template \
    > /home/mlab/env

# Launch all the M-Lab containers
cd /home/mlab
docker compose --profile ndt --env-file env up
