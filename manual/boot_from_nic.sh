#!/bin/bash
#
# Configure the machine to boot from the NIC, then reboot the machine.
#
# There are possibly superfluous sleeps thrown all over the place in here
# because iDRAC seem terribly flaky and unpredictable, so the sleeps are just to
# be sure that the previous command completed and the internal state of the
# iDRAC is mostly settled before moving on to the next command. It's unclear if
# this helps anything, but it can't hurt.

set -x

DRAC_IP=${1:?Error provide drac IP}
DRAC_PASSWORD=${2:?Error provide drac password}

# Maximum number of times to rety any given iDRAC command before giving up.
MAX_RETRIES=5

function racadm() {
    local ip=$1
    local passwd=$2
    shift 2
    idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} $@
}

echo "NOTE: you may want to open the virtual console to watch the system boot."

# Stop the server to quiet all systems.
racadm ${DRAC_IP} ${DRAC_PASSWORD} serveraction powerdown

sleep 10

# TODO: Be sure that BIOS versions are consistent across the platform.
#
# Because we have inconsistent BIOS versions on platform nodes, not every BIOS
# has all the same options. Some BIOSs appear to have an option BootOptionRom
# that must be enabled in order to set the NIC as a boot device. Other BIOSs
# seem to not have this option, but instead have the option LegacyBootProto,
# which likewise must be set to "PXE" (default seems to be "None") in order to
# set the NIC as the first boot device. If either one of these options doesn't
# exist in the BIOS, then the command should benignly fail, but this makes sure
# that at least one of them, maybe both, get set.
# 
# First make sure that the option exists and that the value isn't what we want
# already. If it does exist and isn't set correctly then, try MAX_RETRIES to set
# it to what we want. We attempt this multiple times due to observed flakiness
# in the ability of any given command to succeed any given time.

# Track how many changes to the BIOS were actually made, because if we don't
# make any changes and then try schedule a job in the jobqueue, we will get an
# error.
MOD_COUNT=0

COUNT=0
STATUS=$(racadm ${DRAC_IP} ${DRAC_PASSWORD} get nic.nicconfig.1.bootoptionrom)
if [[ "$?" == "0" ]]; then
  if ! echo "$STATUS" | grep 'bootoptionrom=Enabled'; then
    until racadm ${DRAC_IP} ${DRAC_PASSWORD} set nic.nicconfig.1.bootoptionrom Enabled; do
      COUNT=$((COUNT + 1))
      if [[ "$COUNT" == "$MAX_RETRIES" ]]; then
        echo "Max retry count reached for setting BootOptionRom to Enabled."
        exit 1
      fi
      sleep 5
    done
    MOD_COUNT=$((MOD_COUNT + 1))
  fi
fi

sleep 5

COUNT=0
STATUS=$(racadm ${DRAC_IP} ${DRAC_PASSWORD} get nic.nicconfig.1.legacybootproto)
if [[ "$?" == "0" ]]; then
  if ! echo "$STATUS" | grep 'legacybootproto=PXE'; then
    until racadm ${DRAC_IP} ${DRAC_PASSWORD} set nic.nicconfig.1.legacybootproto PXE; do
      COUNT=$((COUNT + 1))
      if [[ "$COUNT" == "$MAX_RETRIES" ]]; then
        echo "Max retry count reached for setting LegacyBootProto to PXE."
        exit 1
      fi
      sleep 5
    done
    MOD_COUNT=$((MOD_COUNT + 1))
  fi
fi

sleep 5

# Create the jobqueue entry, then powerup, but only if we actually made any
# changes.
if [[ "$MOD_COUNT" > 0 ]]; then
  racadm ${DRAC_IP} ${DRAC_PASSWORD} jobqueue create NIC.Slot.1-1-1 -r pwrcycle -s TIME_NOW
  # Give the machine a while to powerup and make the BIOS config change. 180
  # seconds is arbitrary, and may be too much, though likely not too little.
  sleep 180
fi

# Power the machine back down and set the first boot device to be the NIC.
racadm ${DRAC_IP} ${DRAC_PASSWORD} serveraction powerdown

sleep 5

# This command sometimes fails for no apparent reason. Try it a few times before
# giving up.
COUNT=0
until racadm ${DRAC_IP} ${DRAC_PASSWORD} set bios.biosbootsettings.bootseq NIC.Slot.1-1-1; do
  COUNT=$((COUNT + 1))
  if [[ "$COUNT" == "$MAX_RETRIES" ]]; then
    echo "Max retry count reached for setting first boot device as NIC."
    exit 1
  fi
  sleep 5
done

racadm ${DRAC_IP} ${DRAC_PASSWORD} jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW
