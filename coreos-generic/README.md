## Customize CoreOS images

The `customize_coreos_pxe_image.sh` script will download the latest stable
CoreOS images and generate a customized version by adding the provided cloud
config file to /usr/share/oem/cloud-config.yml

You must run as root to guarantee that file permissions are preserved during the
unpacking and repacking.
```
$ sudo ./customize_coreos_pxe_image.sh \
    build/coreos_custom_pxe_image.cpio.gz
```

After downloading and generating these images, you should upload the new cpio
files and the vmlinuz image to gs://epoxy-mlab-staging/coreos-generic/.

The default cache timeout is 1h. If you need to iterate more often than once an
hour, you must disable caching or you'll get the cached image during boot.

```
CACHE_CONTROL="Cache-Control:private, max-age=0, no-transform"
gsutil -h "$CACHE_CONTROL" \
    cp -r build/coreos_custom_pxe_image.cpio.gz \
          build/coreos_production_pxe.vmlinuz \
          gs://epoxy-mlab-staging/coreos-generic/
```

NOTE: The CoreOS kernel and cpio image must be updated at the same time.
Mismatched versions may fail to boot or behave incorrectly.
