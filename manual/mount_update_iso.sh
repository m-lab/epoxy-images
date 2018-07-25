#!/bin/bash
#
# Script to mount the ISO image via the DRAC using `vmcli` and `idracadm`.

DRAC_IP=${1:?Error provide drac IP}
DRAC_PASSWORD=${2:?Error provide drac password}
DRAC_ISO=${3:?Error provide ISO image}

function racadm() {
    local ip=$1
    local passwd=$2
    shift 2
    idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} $@
}

echo "NOTE: you may want to open the virtual console to watch the system boot"

# Stop the server to quiet all systems.
racadm ${DRAC_IP} ${DRAC_PASSWORD} serveraction powerdown

# Prepare the DRAC to boot from virtual media.
racadm ${DRAC_IP} ${DRAC_PASSWORD} set idrac.VirtualMedia.BootOnce enabled
racadm ${DRAC_IP} ${DRAC_PASSWORD} set idrac.ServerBoot.BootOnce Enabled
racadm ${DRAC_IP} ${DRAC_PASSWORD} set idrac.ServerBoot.FirstBootDevice vCD-DVD
racadm ${DRAC_IP} ${DRAC_PASSWORD} get idrac.VirtualMedia
racadm ${DRAC_IP} ${DRAC_PASSWORD} get idrac.ServerBoot


IMAGE=$( basename "${DRAC_ISO}" )

# Mount virtual media in background.
vmcli -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} -c "/images/${IMAGE}" &

# Power system back up to boot.
sleep 10
racadm ${DRAC_IP} ${DRAC_PASSWORD} serveraction powerup

wait
