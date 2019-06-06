# CoreOS image

The `shim.sh` file exists to aid in the debugging of CNI plugins. It must be
enabled manually.

For example, add a new parameter `--cni-bin-dir=/usr/shimcni/bin` to the `KUBELET_KUBECONFIG_ARGS` in the `10-kubeadm.conf` systemd unit file:
`/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`

```sh
Environment="KUBELET_KUBECONFIG_ARGS=--node-labels=mlab/machine=mlab4,mlab/site=den04,mlab/metro=den,mlab/type=platform --dynamic-config-dir=/var/lib/kubelet/dynamic-configs --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
```

Then restart the kubelet:

```sh
systemctl daemon-reload
systemctl restart kubelet
```
