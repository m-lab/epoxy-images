#!/bin/bash

set -euxo pipefail

METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
CURL_FLAGS=(--header "Metadata-Flavor: Google" --silent)

# Names for project metadata. CA_HASH will be project metadata.
CA_HASH_NAME="platform_cluster_ca_hash"

export PATH=$PATH:/opt/bin:/opt/mlab/bin
export KUBECONFIG=/etc/kubernetes/admin.conf

# Fetch any necessary data from the metadata server.
export cluster_data=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/cluster_data")
export external_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/access-configs/0/external-ip")
export internal_ip=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/network-interfaces/0/ip")
export machine_name=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/name")
export project=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/project-id")
zone_path=$(curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/zone")
export zone=${zone_path##*/}

# Extract cluster/machine data from $cluster_data.
export cluster_cidr=$(echo "$cluster_data" | jq --raw-output '.cluster_attributes.cluster_cidr')
export create_role=$(echo "$cluster_data" | jq --raw-output ".zones[\"${zone}\"].create_role")
export lb_dns=$(echo "$cluster_data" | jq --raw-output '.cluster_attributes.lb_dns')
export token_server_dns=$(echo "$cluster_data" | jq --raw-output '.cluster_attributes.token_server_dns')
export service_cidr=$(echo "$cluster_data" | jq --raw-output '.cluster_attributes.service_cidr')

# Determine the k8s version by inspecting the version of the local kubectl.
k8s_version=$(kubectl version --client=true --output=json | jq --raw-output '.clientVersion.gitVersion')

# The internal DNS name of this machine.
internal_dns="api-platform-cluster-${zone}.${zone}.c.${project}.internal"

# If this file exists, then the cluster must already be initialized. The
# systemd service unit file that runs this script also has a conditional check
# for this file and should not run if it exists. This is just a backup,
# redundant check, just in case for some reason the file exists but the service
# unit gets run anyway. This happened to me (kinkade), where a small bug in the
# configurations caused this service to run, even though this file existed, and
# kubeadm overwrote that file and others before finally erroring out due a
# preflight check failure.
if [[ -f /etc/kubernetes/admin.conf ]]; then
  exit 0
fi

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
# Adds a control plane machine to the load balancer.
#
function add_machine_to_lb() {
  local project=$1
  local zone=$2

  # Having to do this here rather than in Terraform is due to an undesirable
  # behavior of GCP forwarding rules. Backend machines of a load balancer cannot
  # communicate normally with the load balancer itself, and requests to the load
  # balancer IP are reflected back to the backend machine making the request,
  # whether its health check is passing or not. This means that when a machine
  # is trying to join the cluster and needs to communicate with the existing
  # cluster to get configuration data, it is actually tring to communicate with
  # itself, but it is not yet created so gets a connection refused error.
  gcloud compute instance-groups unmanaged add-instances api-platform-cluster-$zone \
    --instances api-platform-cluster-$zone --zone $zone --project $project
}

# Label and/or annotate the node as necessary. This is farmed out as a function
# instead of just residing at the end of the script, which is common to all
# control plane nodes because the label mlab/type=virtual must be applied to the
# initial control plane node _before_ running apply_k8s_configs.sh. Without his
# label, flannel will not deploy on the node, causing other workloads to fail to
# start, causing the script to fail as a whole.
function label_node() {
  kubectl annotate node "$machine_name" flannel.alpha.coreos.com/public-ip-overwrite="$external_ip"
  kubectl label node "$machine_name" mlab/type=virtual
}

#
# Fetches a cluster bootstrap join token from the token server.
#
function get_bootstrap_token() {
  local last_boot=$(date --utc +%Y-%m-%dT%T.%NZ)
  local extension_v1="{\"v1\":{\"last_boot\":\"${last_boot}\"}}"
  local token

  token=$(
    curl --data "$extension_v1" "http://${token_server_dns}:8800/v1/allocate_k8s_token"
  )

  if [[ -z $token ]];then
    echo "Failed to get a bootstrap join token from the token-server"
    exit 1
  fi

  echo "$token"
}

#
# Initializes cluster on the first control plane machine.
#
function initialize_cluster() {
  local ca_cert_hash
  local cert_key
  local join_command
  local instance_exists

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

  # Add this machine to the load balancer before intializing the cluster.
  add_machine_to_lb $project $zone

  kubeadm init --config kubeadm-config.yml --upload-certs

  # Add the shared cert_key to the "secondary" control plane nodes' metadata.
  for z in $(echo "$cluster_data" | jq --join-output --raw-output '.zones | keys[] as $k | "\($k) "'); do
    if [[ $z != $zone ]]; then

      # Wait until the instance exists before trying to add metadata to it.
      instance_exists=""
      until [[ -n $instance_exists ]]; do
        sleep 5
        instance_exists=$(
          gcloud compute instances describe "api-platform-cluster-${z}" \
            --project $project --zone $z --format "value(name)"
        )
      done

      # Add cert_key to cluster_data, then push cluster_data
      echo $cluster_data | \
        jq ".cluster_attributes += {\"cert_key\": \"${cert_key}\"}" > ./cluster-data.json
      gcloud compute instances add-metadata "api-platform-cluster-${z}" \
        --metadata-from-file "cluster_data=cluster-data.json" \
        --project $project \
        --zone $z
    fi
  done

  # Determine the CA cert hash. We could calculate this manually using a long
  # chain of openssl commands, but having kubeadm calculate it helps ensure that
  # we always get the right hash, even if the underlying hash algorithm changes
  # between k8s versions.
  join_command=$(kubeadm token create --ttl 1s --print-join-command)
  export ca_cert_hash=$(echo "$join_command" | egrep -o 'sha256:[0-9a-z]+')

  # Add node labels and annotations.
  label_node

  # Add non-private metadata to the project that will be used by other machines.
  gcloud compute project-info add-metadata --metadata "${CA_HASH_NAME}=${ca_cert_hash}" --project $project
  gcloud compute project-info add-metadata --metadata "lb_dns=${lb_dns}" --project $project
  gcloud compute project-info add-metadata --metadata "token_server_dns=${token_server_dns}" --project $project

  # TODO (kinkade): the only thing using these admin cluster credentials is
  # Cloud Build for the k8s-support repository, which needs to apply
  # workloads to the cluster. We need to find a better way for Cloud Build to
  # authenticate to the cluster so that we don't have to store admin cluster
  # credentials in GCS.
  gsutil -h "$cache_control" cp /etc/kubernetes/admin.conf "gs://k8s-support-${project}/admin.conf"

  # Apply the flannel DamoneSets and related resources to the cluster so that
  # cluster networking will come up. Without it, nodes will never consider
  # themselves ready.
  cd /tmp
  git clone https://github.com/m-lab/k8s-support
  cd k8s-support
  source manage-cluster/k8s_deploy.conf
  jsonnet k8s/roles/flannel.jsonnet | jq '.[]'  > flannel-rbac.json
  jsonnet --ext-str "K8S_CLUSTER_CIDR=${K8S_CLUSTER_CIDR}" config/flannel.jsonnet > flannel-configmap.json
  jsonnet --ext-str "K8S_FLANNEL_VERSION=${K8S_FLANNEL_VERSION}" k8s/daemonsets/core/flannel-virtual.jsonnet > flannel-virtual.json
  jsonnet --ext-str "K8S_FLANNEL_VERSION=${K8S_FLANNEL_VERSION}" k8s/daemonsets/core/flannel-physical.jsonnet > flannel-physical.json
  kubectl apply --filename flannel-rbac.json,flannel-configmap.json,flannel-virtual.json,flannel-physical.json
}

#
# Joins a control plane machine to an existing cluster.
#
function join_cluster() {
  local api_status=""
  local ca_cert_hash
  local cert_key
  local cluster_data
  local join_command="null"
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

  # Once the first API endpoint is up, it still has some housekeeping work to
  # do before other control plane machines are ready to joing the cluster. Give
  # it a bit to finish.
  sleep 90

  token=$(get_bootstrap_token)
  ca_cert_hash=$(
    curl "${CURL_FLAGS[@]}" "${METADATA_URL}/project/attributes/${CA_HASH_NAME}"
  )
  cert_key=$(
    curl "${CURL_FLAGS[@]}" "${METADATA_URL}/instance/attributes/cluster_data" |
      jq --raw-output '.cluster_attributes.cert_key'
  )

  # Replace the token and CA cert has variables in the kubeadm config file.
  sed -i -e "s|{{TOKEN}}|$token|" \
         -e "s|{{CA_CERT_HASH}}|$ca_cert_hash|" \
         -e "s|{{CERT_KEY}}|$cert_key|" \
         ./kubeadm-config.yml

  # Join the machine to the existing cluster.
  kubeadm join --config kubeadm-config.yml

  # Add node labels and annotations.
  label_node

  # Now that the API should be up and running on this machine, add it to the
  # load balancer.
  add_machine_to_lb $project $zone
}

function main() {
  if [[ $create_role == "init" ]]; then
    initialize_cluster
  else
    # If the create_role isn't "init", then it will be "join".
    join_cluster
  fi

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
}

# Run main()
main
