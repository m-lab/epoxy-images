The `shim.sh` file exists to aid in the debugging of CNI plugins.  It will
likely be turned on in production for a while, but eventually the kubelet on
the node should be set up to use the files in `/usr/cni/bin` instead of
`/usr/shimcni/bin`.
