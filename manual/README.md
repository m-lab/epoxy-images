# Flashing the Mellanox ROM

NOTE: The Java Virtual Console Applet no longer works. Instead, we mount the
virtual media locally and use the HTML5 Virtual Console.

Outline of steps:

* Register node with ePoxy server.
* Download Mellanox ROM update ISO from GCS.
* Turn off IP-blocking on the iDRAC.
* Build the epoxy-racadm image.
* Run the epoxy-racadm image to set node to boot from NIC.
* Run the epoxy-racadm container to update Mellanox ROM.
* Start a virtual console to the node.
* Run Mellanox ROM update from virtual console.
* Reboot the machine.


## Register Machine with ePoxy Server
On first boot, the ipxe firmware will try to contact the ePoxy server but the
request will be rejected with a "Not Found" error until the machine is
registered with the ePoxy server.

To add a new machine to the ePoxy data store using the default settings:
```
go get github.com/m-lab/epoxy/cmd/epoxy_admin
$GOPATH/bin/epoxy_admin -project <project> -hostname <fqdn> \
    -address <ipv4-addr>
```

If the `go get` command above yields some errors like
`undefined: proto.InternalMessageInfo`, then one (or both) of these things may
fix it:
```
go get -u github.com/golang/protobuf/{proto,protoc-gen-go}
go get -u google.golang.org/grpc/health/grpc_health_v1
```

To add custom boot or update stage targets, see the help text.

## Download the Mellanox ROM update ISO(s)
Mellanox ROM update ISOs are created by a separate process (by Travis-CI builds,
currently). Before you start this process, download the ISO for the machine in
question from GCS. Images are stored in GCS in this bucket:
```
epoxy-<project>/stage3_mlxupdate_iso
```

## Turn off IP-blocking on the iDRAC
All platform iDRACs should be restricted to only allow access from the IP
address of eb.measurementlab.net. Before starting this process, unrestrict the
iDRAC with something like:
```
/admin1-> racadm set idrac.ipblocking.rangeenable disabled
```

There is also [a script in the m-lab/mlabops repository](https://github.com/m-lab/mlabops/blob/master/drac_ipblock) which can assist in locking and unlocking the iDRACs.

## Build the epoxy-racadm image
```
docker build -t epoxy-racadm .
```

## Run the epoxy-racadm image to set node to boot from NIC
Run the epoxy-racadm container to configure the node to boot from the NIC. When
this script has finished running, the machine _should_ be configured to boot
from the NIC first, but keep your eye on the terminal output for errors because
configuring iDRACs is seemingly flaky and unstable.
```
docker run --rm --volume $PWD:/scripts -it epoxy-racadm \
    /scripts/boot_from_nic.sh ${DRAC_IP} ${DRAC_PASSWORD}
```

## Run the epoxy-racadm container to update Mellanox ROM
Run the epoxy-racadm container with a Mellanox ROM update ISO image, for
example, in ~/Downloads (use whichever directory your ISO image resides in).
```
docker run --rm --volume ~/Downloads:/images --volume $PWD:/scripts -it epoxy-racadm \
    /scripts/mount_update_iso.sh ${DRAC_IP} ${DRAC_PASSWORD} \
    /images/<node>.<site>.measurement-lab.org_mlxupdate.iso
```

## Start a virtual console to the node
Recent changes in Java security have made it impossible to run the old Java
webstart applet. However, newer iDRACs support an HTML5 mode. It is possible to
set the virtual console type using the following command. However, you will
still need to login to the iDRAC via a browser to launch the console.
```
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    set idrac.virtualconsole.plugintype 2
```

## Run Mellanox ROM update from virtual console
First-time updates are not yet automated. So, login in as `root` and run:
```
/usr/local/util/updaterom.sh
```

## Reboot the machine
If everything has gone correctly, the machine will boot from the NIC, contact
the ePoxy server, boot, and automatically join the platform cluster.


# Manually generating ePoxy images
Run the script `manually_generate_images`. This script must be run on a GCE VM
in the same project you are building for. Make it a powerful VM so that the
building process happens much more quickly, and since we will be deleting the VM
as soon as we are done with it, we aren't worried about the cost. n1-standard-8
is probably good enough. When creating the VM, be sure to give the VM full
access to all APIs (enable all scopes). When the VM is up and running, copy this
script to it, edit the variables in the top section to suit your needs then run it.
```
$ ./manually_generate_images.sh
```

