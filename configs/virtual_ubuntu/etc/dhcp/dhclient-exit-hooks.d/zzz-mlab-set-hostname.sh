#!/bin/bash
#
# Explicitly sets the machine's hostname to the FQDN. In GCP, even if you
# create a VM with a FQDN hostname specification, the VM's comes with a
# baked-in Google script which will truncate the domain and make the machine's
# hostname equal to anything up to the first dot. When no node name is
# specified kubeadm falls back on using the hostname of the machine as the node
# name. We don't want the short name to be the k8s node name, but instead its
# FQDN. This small dhclient exit hook sets the hostname to the FQDN, which
# should cause kubeadm to use the correct node name.

hostnamectl set-hostname $(hostname --fqdn)

