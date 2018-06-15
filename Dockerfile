FROM ubuntu:16.04
RUN apt-get update --fix-missing
RUN apt-get install -y unzip python-pip git vim-nox make autoconf gcc mkisofs \
    lzma-dev liblzma-dev autopoint pkg-config libtool autotools-dev upx-ucl \
    isolinux bc texinfo libncurses5-dev linux-source debootstrap gcc-4.8 \
    strace cpio squashfs-tools curl lsb-release gawk \
    linux-source-4.4.0=4.4.0-104.127 golang-1.9
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/go-1.9/bin
ENV GOROOT /usr/lib/go-1.9
# TODO: remove pinned version on linux-source-4.4.0.
#       https://github.com/m-lab/epoxy-images/issues/16
