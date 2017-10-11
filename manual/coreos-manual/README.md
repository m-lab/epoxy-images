## Customize CoreOS images

The `customize_coreos_pxe_image.sh` script will download the latest stable
CoreOS images and generate a customized version by adding the provide cloud
config file to /usr/share/oem/cloud-config.yml

```
$ ./customize_coreos_pxe_image.sh \
    $PWD/cloud-config-mlab1-lga0t.yml \
    $PWD/coreos_mlab1.lga0t.measurement-lab.org_pxe_image.cpio.gz
```

After generating these images, upload the new cpio files and the vmlinuz image
to gs://epoxy-mlab-staging/coreos-manual/.

NOTE: The CoreOS kernel and cpio image must be updated at the same time.
Mismatched version will fail to boot or behave incorrectly.

```
  coreos_mlab1.lga0t.measurement-lab.org_pxe_image.cpio.gz
  coreos_mlab2.lga0t.measurement-lab.org_pxe_image.cpio.gz
  coreos_production_pxe.vmlinuz
```
