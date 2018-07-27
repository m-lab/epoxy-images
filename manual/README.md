# Flashing the Mellanox ROM

NOTE: The Java Virtual Console Applet no longer works. Instead, we mount the
virtual media locally and use the HTML5 Virtual Console.

Outline of steps:

* Register node with ePoxy server.
* Download Mellanox ROM update ISO from GCS.
* Turn off IP-blocking on the iDRAC.
* Build and run the racadm container locally.
* Start a virtual console to the node.
* Run Mellanox ROM update from virtual console
* Exit Docker container and start a new one.
* Update Boot Sequence and reboot machine.


## Register Machine with ePoxy Server
On first boot, the ipxe firmware will try to contact the ePoxy server but the
request will be rejected with a "Not Found" error until the machine is
registered with the ePoxy server.

To add a new machine to the ePoxy data store using the default settings:
```
go get github.com/m-lab/epoxy/cmd/epoxy_admin
$GOPATH/bin/epoxy_admin -project mlab-sandbox -hostname <fqdn> \
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

## Build and run the racadm container locally.
```
docker build -t epoxy-racadm.
```

Run the epoxy-racadm container with a Mellanox ROM update ISO image, for
example, in ~/Downloads (use whichever directory your ISO image resides in).
```
docker run -v ~/Downloads:/images -v $PWD:/scripts -it epoxy-racadm \
    /scripts/mount_update_iso.sh ${DRAC_IP} ${DRAC_PASSWORD} \
    ~/Downloads/mlab1.iad1t.measurement-lab.org_mlxupdate.iso
```

## Start a virtual console to the node.
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

## Exit Docker container and start a new one.
Once the ROM has been flashed, the docker container you started to boot the node
to the ISO through virtual media will just hang, waiting. You'll need to Ctrl-c
out of that container (you may also like to delete the container). Start a new
container for running the commands in the next section.
```
docker run -it epoxy-racadm /bin/bash
```

## Update boot sequence and reboot machine
Power off the server.
```
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} serveraction powerdown
```

Make sure that the BootOptionROM setting for the NIC is enabled
```
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    get nic.nicconfig.1.bootoptionrom
```

If it is enabled, continue to the next step. If it is disabled, you will need to
do these steps before you can set the NIC to be the first boot device.
```
idracadm -r ${DRAC_IP} -u admin -p  ${DRAC_PASSWORD} \
    set nic.nicconfig.1.bootoptionrom Enabled
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    jobqueue create NIC.Slot.1-1-1
```
Power up the machine so that the BIOS can be updated by the job we just created.
```
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} serveraction powerup
```
Once the BIOS is updated by the job we created, power the machine back down,
then proceed with setting the NIC to be the first boot device.
```
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} serveraction powerdown
```

Set the boot sequence to only include the NIC.
```
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    get bios.biosbootsettings
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    set bios.biosbootsettings.bootseq NIC.Slot.1-1-1
```

Create a job that will run on the next boot.
```
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    jobqueue create BIOS.Setup.1-1
```

Power up the machine.
```
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} serveraction powerup
```

If everything has gone correctly, the machine will boot from the NIC, contact
the ePoxy server, boot, and automatically join the platform cluster.
