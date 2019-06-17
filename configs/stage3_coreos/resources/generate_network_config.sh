#!/bin/bash
#
# generate_network_config.sh finds the epoxy.ip= kernel parameter, parses it and
# writes a networkd configuration file for the static IP to the named file.
# generate_network_config also sets the machine hostname.

OUTPUT=${1:?Please provide the name for writing config file}

# TODO: Modify ePoxy to recognize both IPv4 and IPv6 addresses when
# authenticating requests from nodes. For nodes in an environment where an
# upstream device may have IPv6 autoconfiguration/discovery turned on, the node
# may get an autoconf address which is not the one we use for the node.
# Additionally, when we finally configure IPv6 on nodes, if ePoxy is not
# configured to recognize both IPv4 and IPv6 addresses, then requests from
# legitimate nodes from IPv6 addresses will fail.
#
# Disable IPv6 autoconf.
echo "0" > /proc/sys/net/ipv6/conf/all/accept_ra
echo "0" > /proc/sys/net/ipv6/conf/all/autoconf

# Extract the epoxy.ip= parameter from /proc/cmdline.
#
# For example:
#   epoxy.ip=4.14.159.99::4.14.159.65:255.255.255.192:mlab3.lga0t.measurement-lab.org:eth0:off:8.8.8.8:8.8.4.4
if [[ `cat /proc/cmdline` =~ epoxy.ip=([^ ]+) ]]; then
    FIELDS=${BASH_REMATCH[1]}
else
    # Use default values for VM testing.
    FIELDS="192.168.0.2::192.168.0.1:255.255.255.192:localhost:eth0:off:8.8.8.8:8.8.4.4"
fi

# Extract all helpful fields.
IPV4ADDR=$( echo $FIELDS | awk -F: '{print $1}' )
GATEWAY=$( echo $FIELDS | awk -F: '{print $3}' )
HOSTNAME=$( echo $FIELDS | awk -F: '{print $5}' )
DNS1=$( echo $FIELDS | awk -F: '{print $8}' )
DNS2=$( echo $FIELDS | awk -F: '{print $9}' )

# Note, we cannot set the hostname via networkd. Use hostnamectl instead.
hostnamectl set-hostname ${HOSTNAME}

# According to https://systemd.network/systemd.link.html, TSO can only be
# enabled or set to the kernel default when using networkd. We need to disable
# it, thus we use ethtool instead.
ethtool -K eth0 tso off

# TODO: do not hardcode /26.
# TODO: do not hardcode eth0.
cat > ${OUTPUT} <<EOF
[Match]
Name=eth0

[Network]
Address=$IPV4ADDR/26
Gateway=$GATEWAY
DNS=$DNS1
DNS=$DNS2
IPv6AcceptRA=no
EOF
