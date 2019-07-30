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

# Extract the epoxy.hostname parameter from /proc/cmdline
if [[ `cat /proc/cmdline` =~ epoxy.hostname=([^ ]+) ]]; then
  HOSTNAME=${BASH_REMATCH[1]}
else
  HOSTNAME="localhost"
fi

# IPv4
#
# Extract the epoxy.ip= parameter from /proc/cmdline.
#
# For example:
#   epoxy.ipv4=4.14.159.86/26,4.14.159.65,8.8.8.8,8.8.4.4
if [[ `cat /proc/cmdline` =~ epoxy.ipv4=([^ ]+) ]]; then
    FIELDS_IPv4=${BASH_REMATCH[1]}
else
    # Use default values for VM testing.
    FIELDS_IPv4="192.168.0.2,192.168.0.1,8.8.8.8,8.8.4.4"
fi

# Extract all helpful IPv4 fields.
ADDR_IPv4=$( echo $FIELDS_IPv4 | awk -F, '{print $1}' )
GATEWAY_IPv4=$( echo $FIELDS_IPv4 | awk -F, '{print $2}' )
DNS1_IPv4=$( echo $FIELDS_IPv4 | awk -F, '{print $3}' )
DNS2_IPv4=$( echo $FIELDS_IPv4 | awk -F, '{print $4}' )

# IPv6
#
# Extract the epoxy.ipv6= parameter from /proc/cmdline.
#
# For example:
#   epoxy.ipv6=2001:1900:2100:2d::86/64,2001:1900:2100:2d::1,2001:4860:4860::8888,2001:4860:4860::8844
if [[ `cat /proc/cmdline` =~ epoxy.ipv6=([^ ]+) ]]; then
    FIELDS_IPv6=${BASH_REMATCH[1]}
fi

# Extract all helpful IPv6 fields.
ADDR_IPv6=$( echo $FIELDS_IPv6 | awk -F, '{print $1}' )
GATEWAY_IPv6=$( echo $FIELDS_IPv6 | awk -F, '{print $2}' )
DNS1_IPv6=$( echo $FIELDS_IPv6 | awk -F, '{print $3}' )
DNS2_IPv6=$( echo $FIELDS_IPv6 | awk -F, '{print $4}' )


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
# IPv4
Address=$ADDR_IPv4
Gateway=$GATEWAY_IPv4
DNS=$DNS1_IPv4
DNS=$DNS2_IPv4

# IPv6
Address=$ADDR_IPv6
Gateway=$GATEWAY_IPv6
DNS=$DNS1_IPv6
DNS=$DNS2_IPv6
IPv6AcceptRA=no
EOF
