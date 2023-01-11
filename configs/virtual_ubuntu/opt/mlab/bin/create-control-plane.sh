#!/bin/bash

set -euxo pipefail

METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

# Query the local api-server to find out its status.
status=$(
  curl --insecure --output /dev/null --silent --write-out "%{http_code}" \
    https://localhost:6443/readyz || true
)

# If the status is 200, then everything is good to go.
if [[ $status == "200" ]]; then
  exit 0
fi

# Collect or create environment data
api_zones=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/api_zones")
# Create the shared key used to encrypt all the PKI data that will be uploaded
# to the cluster as secrets. This allow kubeadm to upload the data to the
# cluster safely obviating the need for an operator to somehow transfer all
# this data to each control plane machine manually.
cert_key=$(kubeadm certs certificate-key)
cluster_cidr=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/cluster_cidr")
create_role=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/create_role")
external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/access-configs/0/external-ip")
internal_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/ip")
k8s_version=$(kubectl version --client=true --output=json | jq -r '.clientVersion.gitVersion')
lb_url=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/lb_url")
machine_name=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/name")
project=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/project-id")
service_cidr=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/service_cidr")
zone_path=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/zone")
zone=${zone_path##*/}

# Evaluate the kubeadm config template
sed -e "s|{{PROJECT}}|${project}|g" \
    -e "s|{{INTERNAL_IP}}|${internal_ip}|g" \
    -e "s|{{MACHINE_NAME}}|${machine_name}|g" \
    -e "s|{{LB_URL}}|${lb_url}|g" \
    -e "s|{{K8S_VERSION}}|${k8s_version}|g" \
    -e "s|{{CLUSTER_CIDR}}|${cluster_cidr}|g" \
    -e "s|{{SERVICE_CIDR}}|${service_cidr}|g" \
    -e "s|{{CERT_KEY}}|${cert_key}|g" \
    /opt/mlab/conf/kubeadm-config.yml.template > \
    ./kubeadm-config.yml

if [[ $create_role == "init" ]]; then
  # The template variables {{TOKEN}} and {{CA_CERT_HASH}} are not used when
  # creating the initial control plane node, but kubeadm cannot parse the YAML
  # with the template variables in the file. Here we simply replace the
  # variables with some meaningless text so that the YAML can be parsed. These
  # variables are in the JoinConfiguration section, which isn't used here so
  # the values don't matter.
  sed -i -e 's|{{TOKEN}}|NOT_USED|' \
         -e 's|{{CA_CERT_HASH}}|NOT_USED|' \
         ./kubeadm-config.yml


  kubeadm init --config kubeadm-config.yml --upload-certs

  # Create a join command for each of the other "secondary" control plane nodes
  # and add it to their machines metadata.
  for z in $api_zones; do
    if [[ $z != $zone ]]; then
      join_command=$(kubeadm token create --print-join-command)
      gcloud compute instances add-metadata "api-platform-cluster-${z}" \
        --metadata "join_command=${join_command},cert_key=${cert_key}" \
        --project $project \
        --zone $z
    fi
  done

else
  # If the create_role isn't "init", then it will be "join".

  # Don't try to join the cluster until the first control plane node has
  # successfully initialized the cluster, and the load balancer has the first
  # healthy machine added to its backend.
  api_status=""
  until [[ $api_status == "200" ]]; do
    sleep 5
    api_status=$(
      curl --insecure --output /dev/null --silent --write-out "%{http_code}" \
        https://kinkade-test-lb.mlab-sandbox.measurementlab.net:6443/readyz \
	|| true
    )
  done

  # Don't try to join the cluster until the first control plane node has added
  # the join command to this machine's metadata.
  command_exists=""
  until [[ $command_exists == "200" ]]; do
    sleep 5
    command_exists=$(
      curl --insecure --output /dev/null --silent --write-out "%{http_code}" \
        --header "Metadata-Flavor: Google" \
        "${METADATA_URL}/instance/attributes/join_command" \
        || true
    )
  done

  # Fetch the join command and the certificate key.
  join_command=$($CURL_CMD "${METADATA_URL}/instance/attributes/join_command")
  cert_key=$($CURL_CMD "${METADATA_URL}/instance/attributes/cert_key")
  
  # Extract the token and the CA cert hash from the join command.
  TOKEN=$(echo "$join_command" | egrep -o '[0-9a-z]{6}\.[0-9a-z]{16}')
  CA_CERT_HASH=$(echo "$join_command" | egrep -o 'sha256:[0-9a-z]+')

  # Replace the token and CA cert has variables variables in the kubeadm config file.
  sed -i -e "s|{{TOKEN}}|$TOKEN|" \
         -e "s|{{CA_CERT_HASH}}|$CA_CERT_HASH|" \
         -e "s|{{CERT_KEY}}|$CERT_KEY|" \
         ./kubeadm-config.yml

  # Join the machine to the existing cluster.
  kubeadm join --config kubeadm-config.yml
fi

# Modify the --advertise-address flag to point to the external IP, instead of
# the internal one that kubeadm populated. This is necessary because external
# nodes (and especially kube-proxy) need to know of the control plane node by
# its public IP, even though it is technically running in a private VPC.
sed -i -re "s|(advertise-address)=.+|\1=${external_ip}|" \
  /etc/kubernetes/manifests/kube-apiserver.yaml

# Modify the default --listen-metrics-urls flag to listen on the VPC internal
# IP address (the default is localhost). Sadly, this cannot currently be
# defined in the configuration file, since the only place to define etcd
# extraArgs is in the ClusterConfiguration, which applies to the entire
# cluster, not a single etcd instances in a cluster.
# https://github.com/kubernetes/kubeadm/issues/2036
sed -i -re "/listen-metrics-urls/ s|$|,http://${internal_ip}:2381|" \
  /etc/kubernetes/manifests/etcd.yaml

# Add various cluster environment variables to root's .profile and .bashrc
# files so that etcdctl and kubectl operate as expected without additional
# flags.
bash -c "(cat <<-EOF2
  export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
  export ETCDCTL_API=3
  export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
  export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/peer.crt
  export ETCDCTL_DIAL_TIMEOUT=3s
  export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
  export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/peer.key
  export KUBECONFIG=/etc/kubernetes/admin.conf
EOF2) | tee -a /root/.profile /root/.bashrc"

source /root/.profile

kubectl annotate node "$machine_name" flannel.alpha.coreos.com/public-ip-overwrite="$external_ip"
kubectl label node "$machine_name" mlab/type=virtual

