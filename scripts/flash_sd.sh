#!/usr/bin/env bash
set -euo pipefail

# Format and write SD card.
# Usage: flash_sd.sh /dev/sdX
#
# Refuses to write to obvious root devices.

DEV="${1:-}"
if [[ -z "${DEV}" ]]; then
    echo "Usage: $0 /dev/sdX"
    exit 1
fi

case "${DEV}" in
    /dev/sda|/dev/sda[0-9]*|/dev/nvme*)
        echo "REFUSING to touch ${DEV} (looks like a system disk)"
        exit 1
        ;;
esac

if [[ ! -b "${DEV}" ]]; then
    echo "${DEV} is not a block device"
    exit 1
fi

OUT=out
if [[ ! -f "${OUT}/BOOT.BIN" || ! -f "${OUT}/image.ub" ]]; then
    echo "ERROR: ${OUT}/BOOT.BIN or image.ub missing. Run 'make sdcard' first."
    exit 1
fi

echo "About to write to: ${DEV}"
lsblk "${DEV}" || true
echo
echo "Contents to be written:"
ls -lh "${OUT}/"
echo
read -p "Type 'yes' to continue: " ans
if [[ "${ans}" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# Unmount anything on this device
umount "${DEV}"* 2>/dev/null || true

echo "==> Partitioning"
parted -s "${DEV}" mklabel msdos
parted -s "${DEV}" mkpart primary fat32 1MiB 512MiB
parted -s "${DEV}" mkpart primary ext4 512MiB 100%
parted -s "${DEV}" set 1 boot on
sleep 1

PART_BOOT="${DEV}1"
PART_ROOT="${DEV}2"
[[ "${DEV}" =~ [0-9]$ ]] && PART_BOOT="${DEV}p1" && PART_ROOT="${DEV}p2"

echo "==> mkfs BOOT (FAT32)"
mkfs.vfat -F 32 -n BOOT "${PART_BOOT}"

echo "==> mkfs rootfs (ext4)"
mkfs.ext4 -F -L rootfs "${PART_ROOT}"

echo "==> Mounting and copying"
MNT_BOOT=$(mktemp -d)
MNT_ROOT=$(mktemp -d)
mount "${PART_BOOT}" "${MNT_BOOT}"
mount "${PART_ROOT}" "${MNT_ROOT}"

cp -f "${OUT}/BOOT.BIN" "${MNT_BOOT}/"
cp -f "${OUT}/image.ub" "${MNT_BOOT}/"
[[ -f "${OUT}/system.dtb" ]] && cp -f "${OUT}/system.dtb" "${MNT_BOOT}/"
[[ -f "${OUT}/tdc.bit.bin" ]] && cp -f "${OUT}/tdc.bit.bin" "${MNT_BOOT}/"
[[ -f "${OUT}/coincidence.bit.bin" ]] && cp -f "${OUT}/coincidence.bit.bin" "${MNT_BOOT}/"

if [[ -f "${OUT}/rootfs.tar.gz" ]]; then
    echo "==> Extracting rootfs"
    tar -xzf "${OUT}/rootfs.tar.gz" -C "${MNT_ROOT}"
elif [[ -f "${OUT}/rootfs.ext4" ]]; then
    echo "==> Copying rootfs.ext4"
    dd if="${OUT}/rootfs.ext4" of="${PART_ROOT}" bs=4M status=progress
fi

sync
umount "${MNT_BOOT}"
umount "${MNT_ROOT}"
rmdir "${MNT_BOOT}" "${MNT_ROOT}"

echo
echo "==> Done. SD card ${DEV} is ready."
