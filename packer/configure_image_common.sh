#!/bin/bash
#
# This script gets uploaded and executed on the temporary VM that Packer creates
# when generating custom images. It should do everything necessary to prepare
# the custom image's environment, such as installing necessary binaries and
# configuration files. This script is more or less the equivalent of
# "setup_stage3_ubuntu.sh", but for virtual nodes instead of physical ones.

set -euxo pipefail

source /tmp/config.sh

# A number of important binaries get installed in /opt/bin, so put this
# directory in root's PATH. Additionally, write PATH to .profile and .bashrc so
# that it get loaded on both interactive and non-interactive session.
echo "export PATH=\$PATH:/opt/bin" >> /root/.profile
echo "export PATH=\$PATH:/opt/bin" >> /root/.bashrc

# Adds /opt/bin to the end of the secure_path sudoers configuration.
sed -i -e '/secure_path/ s|"$|:/opt/bin"|' /etc/sudoers

# Install required packages.
apt update
apt install -y \
  apparmor \
  busybox \
  conntrack \
  containerd \
  ebtables \
  iptables \
  jq \
  less \
  socat \
  tmux \
  vim

# Install CNI plugins.
mkdir -p /opt/cni/bin
curl --location "https://github.com/containernetworking/plugins/releases/download/${K8S_CNI_VERSION}/cni-plugins-linux-amd64-${K8S_CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

# Install the Flannel CNI plugin.
# v0.9.1 of the official CNI plugins release stopped including flannel, so we
# must now install it manually from its official source.
curl --location "https://github.com/flannel-io/cni-plugin/releases/download/${K8S_FLANNELCNI_VERSION}/flannel-amd64" > /opt/cni/bin/flannel
chmod +x /opt/cni/bin/flannel

# Install crictl.
mkdir -p /opt/bin
curl --location "https://github.com/kubernetes-incubator/cri-tools/releases/download/${K8S_CRICTL_VERSION}/crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz" | tar -C /opt/bin -xz

# Install kubeadm, kubelet and kubectl.
cd /opt/bin
curl --location --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
chmod +x {kubeadm,kubelet,kubectl}

# Install kubelet systemd service and enable it.
curl --silent --show-error --location \
  "https://github.com/kubernetes/release/blob/${K8S_TOOLING_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" \
  | sed "s:/usr/bin:/opt/bin:g" | sudo tee /etc/systemd/system/kubelet.service

mkdir -p /etc/systemd/system/kubelet.service.d
curl --silent --show-error --location \
  "https://raw.githubusercontent.com/kubernetes/release/${K8S_TOOLING_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf"
  | sed "s:/usr/bin:/opt/bin:g" | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# For convenience, when an operator needs to login and inspect things with crictl.
echo -e "\nexport CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock\n" >> /root/.bashrc

# Enable systemd units
systemctl enable kubelet.service
