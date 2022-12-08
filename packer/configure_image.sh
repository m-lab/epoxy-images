#!/bin/bash

sudo --login

set -euxo pipefail

source /tmp/config.sh

# Binaries will get installed in /opt/bin, put it in root's PATH
# Write it to .profile and .bashrc so that it get loaded on both interactive
# and non-interactive session.
echo "export PATH=\$PATH:/opt/bin" >> /root/.profile
echo "export PATH=\$PATH:/opt/bin" >> /root/.bashrc

# Adds /opt/bin to the end of the secure_path sudoers configuration.
sed -i -e '/secure_path/ s|"$|:/opt/bin"|' /etc/sudoers

# Install required packages.
apt update
apt install -y \
  busybox \
  conntrack \
  containerd \
  ebtables \
  iptables \
  jq \
  less \
  socat \
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
  "https://raw.githubusercontent.com/kubernetes/release/${K8S_TOOLING_VERSION}/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service" \
	| sed "s:/usr/bin:/opt/bin:g" | sudo tee /etc/systemd/system/kubelet.service

mkdir -p /etc/systemd/system/kubelet.service.d
curl --silent --show-error --location \
  "https://raw.githubusercontent.com/kubernetes/release/${K8S_TOOLING_VERSION}/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf" \
	| sed "s:/usr/bin:/opt/bin:g" | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# If this directory doesn't exist, then the kubelet complains bitterly,
# polluting the logs terribly.
mkdir -p /etc/kubernetes/manifests

# The directory where machine metadata will be written, possibly consumed by
# experiments.
mkdir -p /var/local/metadata

# For convenience, when an operator needs to login and inspect things with crictl.
echo "export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock" >> /root/.bashrc

# For some reason the default cgroup driver in containerd is not systemd, and
# when it is not, undefined behavior occurs, in which containers continually
# receive SIGTERM signals from the OS, and they end up on and off in a
# CrashLoopBackoff state.
mkdir /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Enable systemd units
systemctl enable kubelet.service
systemctl enable check-reboot.service
systemctl enable check-reboot.timer
systemctl enable configure-tc-fq.service
systemctl enable write-metadata.service
systemctl enable join-cluster.service
