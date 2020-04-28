FROM centos:7

RUN yum -y update && yum -y install openssl openssl-devel pciutils wget
# Latest as of 2018-06-12:
# https://www.dell.com/support/home/us/en/04/drivers/driversdetails?driverid=f20vm
RUN wget -O /tmp/pkg.tgz https://downloads.dell.com/FOLDER05025571M/1/OM-MgmtStat-Dell-Web-LX-9.1.2-2965_A00.tar.gz
RUN tar -C /tmp -xvf /tmp/pkg.tgz
WORKDIR /tmp/linux/rac/RHEL7/x86_64
RUN yum install -y *.rpm
RUN rm -rf /tmp/*
RUN yum -y clean all
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/dell/srvadmin/bin:/opt/dell/srvadmin/sbin
WORKDIR /
