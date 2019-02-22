#!/bin/bash
#
# flashrom.sh accepts a ROM image and burns it to the local NIC. The NIC must
# be one of ConnectX3 or ConnectX3-Pro models. And, the ROM image must have a
# version strictly greater than the current version.
#
# For more detailed documentation on the MFT commands below, see:
#   http://www.mellanox.com/related-docs/MFT/MFT_user_manual_4_4_0.pdf

set -x
set -e

ROM=${1:?PXE ROM to burn to NIC}
# TODO: is there a better way to identify models?
if [[ -e /dev/mst/mt4099_pci_cr0 ]] ; then
    # ConnectX3, model 4099/0x1003
    DEV=/dev/mst/mt4099_pci_cr0
elif [[ -e /dev/mst/mt4103_pci_cr0 ]] ; then
    # ConnectX3-Pro, model 4103/0x1007
    DEV=/dev/mst/mt4103_pci_cr0
fi
ERROR_DELAY=60
PAUSE=5


# Backup current ROM by "reading" the ROM (rrom) from the local device.
flint --device "${DEV}" rrom current.mrom

# "Query" the new and current ROM versions (qrom).
NEW_VERSION=$( flint --image "${ROM}" qrom )
CUR_VERSION=$( flint --image current.mrom qrom )

echo "ROM Versions:"
echo "   Currently installed: $CUR_VERSION"
echo "   Updating to:         $NEW_VERSION"

# TODO: We must permit rollback or reset, in which case, "NEW_VERSION" could be
# less than or equal to "CUR_VERSION".
#
# NOTE: there are two typical cases:
#  * first ROM update
#  * all subsequent updates
#
# For the first ROM update, the original ROM version will look something like:
#
#   "Rom Info: type=UEFI version=12.18.43 proto=ETH"
#
# In this case, we want to allow the update.
#
# For all other updates, we expect the ROM version to follow a convention like:
#
#   "Rom Info: type=PXE version=3.4.809 devid=4099"
#
# Where higher versions are lexically greater than the current version.
case "${CUR_VERSION}" in
    *type=UEFI*)
        # Allow update unconditionally.
        echo "First ROM update"
    ;;
    *type=PXE*)
        # Allow same-version updates, but not lower version updates.
        if [[ "${NEW_VERSION}" < "${CUR_VERSION}" ]] ; then
            echo "Warning: new ROM version is not greater than current version."
            echo "Taking no action."
            echo "Sleeping $ERROR_DELAY seconds..."
            # TODO(soltesz): log everything.
            sleep $ERROR_DELAY
            exit 0
        fi
    ;;
esac


# NOTE: This is required for configuring systems for the first time. These will
# be a no-ops for previously-updated machines.
# NOTE: port numbers start at 1.
# NOTE: "BOOT_OPTION_ROM_EN" means enable the BIOS PXE option ROM on port 1.
# NOTE: "LEGACY_BOOT_PROTOCOL" means use the "PXE" protocol when booting the
#       option rom on port 1.
echo "Setting device options to PXE boot on PORT 1."
mlxconfig --dev "${DEV}" --yes --show_default set BOOT_OPTION_ROM_EN_P1=True
mlxconfig --dev "${DEV}" --yes --show_default set LEGACY_BOOT_PROTOCOL_P1=PXE

# For debugging, query the device to report current configuration.
echo "Before update"
flint --device "$DEV" query
mlxconfig --dev "$DEV" query
sleep $PAUSE

# Burn ROM to NIC.
echo "Performing update now..."
# NOTE: To prevent the following error on new NICs, we must specify
#      --allow_rom_change.
#
# Error:
#     "Burn ROM failed: The device FW contains common FW/ROM Product Version -
#      The ROM cannot be updated separately."
#
# While it's true that the Firmware "Product Version" is out of sync with a
# custom ROM, but we are building images that are functionally compatible.
#
# NOTE: "Burn" the ROM (brom) to the device.
# TODO: flip out if burning or verifying images fail.
flint --allow_rom_change --device "$DEV" brom "$ROM"
# Verify that the device recognizes the new image.
flint --device "$DEV" verify
sleep $PAUSE

# For debugging, query the device to report new configuration.
echo "After update"
flint --device "$DEV" query
mlxconfig --dev "$DEV" query
sleep $PAUSE

# Perform a final verification that the new ROM matches the expected ROM.
flint --device "$DEV" rrom latest.mrom
diff latest.mrom "$ROM"
