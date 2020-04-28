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

# A small wrapper for idracadm.
function racadm() {
  idracadm -r ${DRAC_IP} -u admin -p ${DRAC_PASSWORD} $@
}

# iDRAC commands seem to randomly fail for no apparent reason. You try it once
# and it fails, and the next time if succeeds. This is a small wrapper that
# will try a command MAX_RETRIES times before giving up and exiting with a
# debug message.
function retry_racadm() {
  local command=$1
  local count=0
  local final_attempt="no"
  local msg=$2

  until racadm "${command}"; do
    count=$((count + 1))
    if [[ "${count}" -ge "${MAX_RETRIES}" ]]; then
      # Try rebooting the machine and resetting the iDRAC, then try MAX_RETRIES
      # again.
      if [[ "${final_attempt}" == "no" ]]; then
        count=0
        racadm serveraction powercycle
        racadm racreset hard -f
        sleep 240
        final_attempt="yes"
      else
        echo "${msg}"
        # Make sure the machine is powered up before we exit.
        racadm serveraction powerup
        exit 1
      fi
    fi
    sleep 5
  done
}

echo "NOTE: you may want to open the virtual console to watch the system boot."

# Stop the server to quiet all systems.
racadm serveraction powerdown

sleep 10

# Check the first boot device. If it's already the NIC, then skip this node.
# Else, record the first boot device and make the it 2nd boot device after the
# NIC later on.
OUTPUT=$(racadm get bios.biosbootsettings.bootseq | grep BootSeq)
ORIG_FIRST_BOOT_DEVICE=$(echo "${OUTPUT}" | cut -d= -f2 | cut -d, -f1)
if [[ $ORIG_FIRST_BOOT_DEVICE == NIC* ]]; then
  echo "First boot device is already the NIC. Nothing to do."
  exit 0
fi

# If the NIC is already in the boot list, then we grab the BIOS key here.
NIC_IN_BOOT_LIST=$(echo $OUTPUT | grep NIC)
if [[ -n $NIC_IN_BOOT_LIST ]]; then
  NIC_BIOS_KEY=$(echo "${OUTPUT}" | egrep -o 'NIC\.Slot\.[0-9]{1}-[0-9]{1}-[0-9]{1}')
else
  # Get the NIC #1's BIOS key
  OUTPUT=$(racadm get nic.nicconfig.1)
  NIC_BIOS_KEY=$(echo "${OUTPUT}" | egrep -o 'NIC\.Slot\.[0-9]{1}-[0-9]{1}-[0-9]{1}')
fi

# Delete any existing jobs, first gently, then forcibly.
racadm jobqueue delete --all

sleep 5

racadm jobqueue delete -i JID_CLEARALL_FORCE

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

# If the NIC is already in the boot list, then we don't need to do any of the following.
if [[ -z $NIC_IN_BOOT_LIST ]]; then
  STATUS=$(racadm get nic.nicconfig.1.bootoptionrom)
  if [[ "$?" -eq "0" ]]; then
    if ! echo "${STATUS}" | grep 'bootoptionrom=Enabled' && \
        ! echo "${STATUS}" | grep ERROR; then
      retry_racadm "set nic.nicconfig.1.bootoptionrom Enabled" \
          "Max retry count reached for setting BootOptionRom to Enabled."
      MOD_COUNT=$((MOD_COUNT + 1))
    fi
  fi

  sleep 5

  STATUS=$(racadm get nic.nicconfig.1.legacybootproto)
  if [[ "$?" -eq "0" ]]; then
    if ! echo "${STATUS}" | grep 'legacybootproto=PXE' && \
        ! echo "${STATUS}" | grep ERROR; then
      retry_racadm "set nic.nicconfig.1.legacybootproto PXE" \
          "Max retry count reached for setting LegacyBootProto to PXE."
      MOD_COUNT=$((MOD_COUNT + 1))
    fi
  fi

  sleep 5

  # Create the jobqueue entry, then powerup, but only if we actually made any
  # changes.
  if [[ "${MOD_COUNT}" -gt 0 ]]; then
    retry_racadm "jobqueue create $NIC_BIOS_KEY -r pwrcycle -s TIME_NOW" \
        "Max retry count reached for setting ${NIC_BIOS_KEY} jobqueue job."
    # Give the machine a while to powerup and make the BIOS config change. 180
    # seconds is arbitrary, and may be too much, though likely not too little.
    sleep 180
  fi
fi

# Power the machine back down and set the first boot device to be the NIC.
racadm serveraction powerdown

sleep 5

retry_racadm "set bios.biosbootsettings.bootseq $NIC_BIOS_KEY,Optical.SATAEmbedded.J-1" \
    "Max retry count reached for setting first boot device as NIC."

sleep 5

retry_racadm "jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW" \
    "Max retry count reached for creating BIOS.Setup.1-1 jobqueue job."
