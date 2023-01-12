#!/bin/bash

set -euxo pipefail

METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

export PATH=$PATH:/opt/bin:/opt/mlab/bin

# Query the local api-server to find out its status.
status=$(
  curl --insecure --output /dev/null --silent --write-out "%{http_code}" \
    https://localhost:6443/readyz || true
)

# If the status is 200, then everything is good to go.
if [[ $status == "200" ]]; then
  exit 0
fi

# Fetch any necessary data from the metadata server.
cluster_data=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/cluster_data")
external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/access-configs/0/external-ip")
internal_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/ip")
machine_name=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/name")
project=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/project-id")
zone_path=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/zone")
zone=${zone_path##*/}

# Extract cluster/machine data from $cluster_data.
cluster_cidr=$(echo "$cluster_data" | jq -r '.cluster_attributes.cluster_cidr')
create_role=$(echo "$cluster_data" | jq -r ".zones[\"${zone}\"].create_role")
lb_dns=$(echo "$cluster_data" | jq -r '.cluster_attributes.lb_dns')
service_cidr=$(echo "$cluster_data" | jq -r '.cluster_attributes.service_cidr')

# Determine the k8s version by inspecting the version of the local kubectl.
k8s_version=$(kubectl version --client=true --output=json | jq -r '.clientVersion.gitVersion')

# The internal DNS name of this machine.
internal_dns="api-platform-cluster-${zone}.${zone}.c.${project}.internal"

# Evaluate the kubeadm config template
sed -e "s|{{PROJECT}}|${project}|g" \
    -e "s|{{INTERNAL_IP}}|${internal_ip}|g" \
    -e "s|{{MACHINE_NAME}}|${machine_name}|g" \
    -e "s|{{LB_DNS}}|${lb_dns}|g" \
    -e "s|{{K8S_VERSION}}|${k8s_version}|g" \
    -e "s|{{CLUSTER_CIDR}}|${cluster_cidr}|g" \
    -e "s|{{SERVICE_CIDR}}|${service_cidr}|g" \
    -e "s|{{INTERNAL_DNS}}|${internal_dns}|g" \
    /opt/mlab/conf/kubeadm-config.yml.template > \
    ./kubeadm-config.yml

#
# Initializes cluster on the first control plane machine.
#
function initialize_cluster() {
  local cert_key
  local join_command

  # Create the shared key used to encrypt all the PKI data that will be
  # uploaded to the cluster as secrets. This allow kubeadm to upload the data
  # to the cluster safely obviating the need for an operator to somehow
  # transfer all this data to each control plane machine manually.
  cert_key=$(kubeadm certs certificate-key)

  # The template variables {{TOKEN}} and {{CA_CERT_HASH}} are not used when
  # creating the initial control plane node, but kubeadm cannot parse the YAML
  # with the template variables in the file. Here we simply replace the
  # variables with some meaningless text so that the YAML can be parsed. These
  # variables are in the JoinConfiguration section, which isn't used here so
  # the values don't matter.
  sed -i -e 's|{{TOKEN}}|NOT_USED|' \
         -e 's|{{CA_CERT_HASH}}|NOT_USED|' \
         -e "s|{{CERT_KEY}}|${cert_key}|g" \
         ./kubeadm-config.yml

  kubeadm init --config kubeadm-config.yml --upload-certs

  # Create a join command for each of the other "secondary" control plane nodes
  # and add it to their machines metadata, along with the shared cert_key.
  for z in $(echo "$cluster_data" | jq --join-output --raw-output '.zones | keys[] as $k | "\($k) "'); do
    if [[ $z != $zone ]]; then
      join_command=$(kubeadm token create --print-join-command)
      echo $cluster_data | \
        jq ".cluster_attributes += {\"join_command\": \"${join_command}\", \"cert_key\": \"${cert_key}\"}" \
	> ./cluster-data.json
      gcloud compute instances add-metadata "api-platform-cluster-${z}" \
        --metadata-from-file "cluster_data=./cluster-data.json" \
        --project $project \
        --zone $z
    fi
  done
}

#
# Joins a control plane machine to an existing cluster.
#
function join_cluster() {
  local api_status
  local ca_cert_hash
  local cert_key
  local cluster_data
  local join_command
  local token

  # Don't try to join the cluster until the initial control plane node has
  # successfully initialized the cluster.
  until [[ $api_status == "200" ]]; do
    sleep 5
    api_status=$(
      curl --insecure --output /dev/null --silent --write-out "%{http_code}" \
        "https://${lb_dns}:6443/readyz" \
	|| true
    )
  done

  # Don't try to join the cluster until the first control plane node has added
  # the join command to this machine's cluster_data metadata.
  until [[ $join_command != "null" ]]; do
    sleep 5
    cluster_data=$(
      curl --insecure --output /dev/null --silent --write-out "%{http_code}" \
        --header "Metadata-Flavor: Google" \
        "${METADATA_URL}/instance/attributes/cluster_data"
    )
    join_command=$(echo "$cluster_data" | jq -r '.cluster_attributes.join_command')
  done

  # Extract the cert_key and join_command from cluster_data.
  cert_key=$(echo "$cluster_data" | jq -r '.cluster_attributes.cert_key')
  join_command=$(echo "$cluster_data" | jq -r '.cluster_attributes.join_command')

  # Extract the token and the CA cert hash from the join command.
  token=$(echo "$join_command" | egrep -o '[0-9a-z]{6}\.[0-9a-z]{16}')
  ca_cert_hash=$(echo "$join_command" | egrep -o 'sha256:[0-9a-z]+')

  # Replace the token and CA cert has variables variables in the kubeadm config file.
  sed -i -e "s|{{TOKEN}}|$token|" \
         -e "s|{{CA_CERT_HASH}}|$ca_cert_hash|" \
         -e "s|{{CERT_KEY}}|$cert_key|" \
         ./kubeadm-config.yml

  # Join the machine to the existing cluster.
  kubeadm join --config kubeadm-config.yml

}

if [[ $create_role == "init" ]]; then
  initialize_cluster
else
  # If the create_role isn't "init", then it will be "join".
  join_cluster
fi

# Now that the API should be up on this node, add this machine to the load
# balancer. Having to do this here rather than in Terraform is due to an
# undesirable behavior of GCP forwarding rules. Backend machines of a load
# balancer cannot communicate normally with the load balancer itself, and
# requests to the load balancer IP are reflected back to the backend machine
# making the request, whether its health check is passing or not. This means
# that when a machine is trying to join the cluster and needs to communicate
# with the existing cluster to get configuration data, it is actually tring to
# communicate with itself, but it is not yet created so gets a connection
# refused error.
gcloud compute instance-groups unmanaged add-instances api-platform-cluster-$zone \
  --instances api-platform-cluster-$zone --zone $zone --project $project

# Modify the --advertise-address flag to point to the external IP, instead of
# the internal one that kubeadm populated. This is necessary because external
# nodes (and especially kube-proxy) need to know of the control plane node by
# its public IP, even though it is technically running in a private VPC.
#
# The kubeadm config includes "advertiseAddress" settings for both initializing
# and joining the cluster. However, we cannot use the external IP for those
# fields because kubeadm uses those same settings to configure etcd, which
# communicates with the other etcd instances on the private network. kubeadm
# allows for some configuration of etcd through the configuration file, but
# unfortunately those settings are cluster-wide, so we cannot set local
# settings via the kubeadm config. Hence this manoeuver.
#
# We could possibly use the --patches flag to kubeadm to get around having to do this:
# https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/#options
sed -i -re "s|(advertise-address)=.+|\1=${external_ip}|" \
  /etc/kubernetes/manifests/kube-apiserver.yaml

# Modify the default --listen-metrics-urls flag to listen on the VPC internal
# IP address (the default is localhost). Sadly, this cannot currently be
# defined in the configuration file, since the only place to define etcd
# extraArgs is in the ClusterConfiguration, which applies to the entire
# cluster, not a single etcd instances in a cluster.
# https://github.com/kubernetes/kubeadm/issues/2036
#
# We could possibly use the --patches flag to kubeadm to get around having to do this:
# https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/#options
sed -i -re "/listen-metrics-urls/ s|$|,http://${internal_ip}:2381|" \
  /etc/kubernetes/manifests/etcd.yaml

# Add various cluster environment variables to root's .profile and .bashrc
# files so that etcdctl and kubectl operate as expected without additional
# flags.
bash -c "(cat <<-EOF
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
export ETCDCTL_API=3
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/peer.crt
export ETCDCTL_DIAL_TIMEOUT=3s
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/peer.key
export KUBECONFIG=/etc/kubernetes/admin.conf
EOF
) | tee -a /root/.profile /root/.bashrc"

# Wait a little while before trying to communicate with the api-server, since
# the modifications to the manifests above will causes restarts of it and etcd,
# and they may not yet be up and running.
sleep 30

export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl annotate node "$machine_name" flannel.alpha.coreos.com/public-ip-overwrite="$external_ip"
kubectl label node "$machine_name" mlab/type=virtual
