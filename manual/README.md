
## Booting from Virtual Media

The Java Virtual Console Applet no longer works. Instead, we mount the virtual
media locally and use the HTML5 Virtual Console.

Steps:

* Login to DRAC
* Open HTML5 Virtual Console
* Run `mount_update_iso.sh`

```
# Build the racadm container locally.
docker build -t epoxy-racadm .

# Run the epoxy-racadm container with an image in ~/Downloads.
docker run -v ~/Downloads:/images -v $PWD:/scripts -it epoxy-racadm \
    /scripts/mount_update_iso.sh ${DRAC_IP} ${DRAC_PASSWORD} \
      ~/Downloads/mlab1.iad1t.measurement-lab.org_mlxupdate.iso
```

It is possible to set the virtual console plugin type using:
```
    # Set the default virtual console type to "HTML5".
    idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
        set idrac.virtualconsole.plugintype 2
```

## Run update

First-time updates are not yet automated. So, login in as `root` and run:

```
/usr/local/util/updaterom.sh
```

## Update Boot Sequence

```
# Power off the server.
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} serveraction powerdown

# Set the boot sequence to only include the NIC.
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    get bios.biosbootsettings
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    set bios.biosbootsettings.bootseq NIC.Slot.1-1-1

# Create a job that will run on the next boot.
idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    jobqueue create BIOS.Setup.1-1

idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} serveraction powerup

```

## Register Machine with ePoxy Server

On first boot, the ipxe firmware will try to contact the ePoxy server but the
request will be rejected with a "Not Found" error until the machine is
registered with the ePoxy server.

To add a new machine to the ePoxy data store using the default settings:
```
   go get github.com/m-lab/epoxy/cmd/epoxy_admin
   epoxy_admin -project mlab-sandbox -hostname <fqdn> -address <ipv4-addr>
```

To add custom boot or update stage targets, see the help text.
