## multus-cni.conf

The `multus-cni.conf` file is included in the `stage3_coreos` image so that it
can be copied to the correct folder as part of the k8s setup script (found [here](https://github.com/m-lab/k8s-support/blob/master/node/setup_k8s.sh.template)).

This file is needed to allow kubelet to join the k8s cluster.

