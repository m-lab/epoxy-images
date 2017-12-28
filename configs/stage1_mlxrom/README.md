Building a custom ROM
==

An example command that will be integrated into the travis build.

```
./setup_stage1.sh \
    /build \
    $PWD/configs/stage1_mlxrom \
    ".*lga0t.*" \
    3.4.800 \
    "$PWD/configs/stage1_mlxrom/giag2new.pem"
```

Certificates
==

iPXE can validate TLS certificates if there is a chain of trust. For iPXE, the
root of trust starts with a certificate embedded in an iPXE ROM. Ordinarily,
distributions ship hundreds of CA certificates so libraries and browsers
can authenticate almost any certificate. But, this is not an option for iPXE
ROMs because they are so space limited.

Since ePoxy needs to interact with only two Google services (GAE for the server,
and GCS to download images), at most we need to embed two trusted CA certs.

As a first iteration, we are embedding two Issuing CAs. The first is the "Google
Internet Authority G2": https://pki.google.com/GIAG2.crt used to sign addresses
under:

 - `*.appspot.com`
 - `*.storage.googleapis.com`

The second Issuing CA is the "Google Internet Authority G3": https://pki.goog/


To inspect these certifiates, download them and use `openssl` to make them
human readable.

```
openssl x509 -in ./gtsgiag3.pem -text -noout
```

This is a short-term solution suitable or testing but unsuitable for wider
deployment or legacy boot-cds. Ultimately, we may use the cross signing certs
maintained by ipxe - http://ipxe.org/crypto or maintain our own set of cross
signed certificates. This will require creating and maintaining a private CA
with a long expiration to support long-term read-only boot-cds.


Mellanox ROMs
==

The ipxe sources are maintained here:

    https://git.ipxe.org/ipxe.git

These upstream sources natively support the ConnectX4 and ConnectX5 models.

Mellanox maintains a branded ipxe fork called "FlexBoot" with drivers
for the Mellanox ConnectX3 models.

    https://git.ipxe.org/vendor/mellanox/flexboot.git

At time of writing it was last updated 2016-07-05 as version "3.4.821". These
sources are more up to date than the branded "FlexBoot" sources published by
Mellanox on their website, last published 2015-05-05 as version "3.4.521".

The flexboot branch of that repo has ipxe sources up to that date.

The `src/arch/x86/prefix/romprefix.S` is missing a critical driver version
definition with magic constants (i.e. "mlxsign:" in hex) required to recognize
valid ROMs by the "Mellanox Firmware Tools" (mft).

    http://www.mellanox.com/page/management_tools

Our build scripts maintain a patch to add the following definition:

```
driver_version:
 .align 16
 .long 0x73786c6d
 .long 0x3a6e6769
 .long __MLX_0001_MAJOR_VER_
 .long __MLX_MIN_SUB_MIN_VER_
 .long __MLX_DEV_ID_00ff
```