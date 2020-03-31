FROM ubuntu:20.04
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update --fix-missing
RUN apt-get install -y unzip python3-pip git vim-nox make autoconf gcc mkisofs \
    lzma-dev liblzma-dev autopoint pkg-config libtool autotools-dev upx-ucl \
    isolinux bc texinfo libncurses-dev linux-source debootstrap gcc \
    strace cpio squashfs-tools curl lsb-release gawk \
    mtools dosfstools syslinux syslinux-utils parted kpartx grub-efi \
    linux-source golang xorriso
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/go/bin
ENV GOROOT /usr/lib/go
RUN mkdir /go
ENV GOPATH /go
# CGO_ENABLED=0 creates a statically linked binary.
# The -ldflags drop another 2.5MB from the binary size.
# -w 	Omit the DWARF symbol table.
# -s 	Omit the symbol table and debug information.
RUN CGO_ENABLED=0 go get -u -ldflags '-w -s' github.com/m-lab/epoxy/cmd/epoxy_client
