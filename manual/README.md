
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
# HTML5
racadm set idrac.virtualconsole.plugintype 2
```

## Run update

First-time updates are not yet automated. So, login in as `root` and run:

```
/usr/local/util/updaterom.sh
```

## Update Boot Sequence

```
# Power off the server.
idracadm7 -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} serveraction powerdown

# Set the boot sequence to only include the NIC.
idracadm7 -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    racadm get bios.biosbootsettings
idracadm7 -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    racadm set bios.biosbootsettings.bootseq NIC.Slot.1-1-1

# Create a job that will run on the next boot.
idracadm7 -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} \
    racadm jobqueue create BIOS.Setup.1-1

idracadm7 -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} serveraction powerup

```
