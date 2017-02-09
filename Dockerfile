FROM ubuntu:16.04
RUN apt-get update
RUN apt-get install -y unzip python-pip git vim-nox make autoconf gcc mkisofs \
    lzma-dev liblzma-dev autopoint pkg-config libtool autotools-dev upx-ucl \
    isolinux bc texinfo libncurses5-dev linux-source debootstrap gcc-4.8 \
    strace cpio
