#!/usr/bin/env bash
set -euo pipefail

# Format and write SD card from ./out/.
# Usage: flash_sd.sh /dev/sdX
#
# Refuses to write to a disk that holds a mounted system partition.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DEV="${1:-}"
if [[ -z "${DEV}" || "${DEV}" == /dev/sdX ]]; then
    echo "Usage: $0 /dev/sdX   (make flash SD=/dev/sdX)" >&2
    echo "Removable disks:" >&2
    lsblk -d -o NAME,SIZE,RM,MODEL | awk 'NR==1 || $3==1' >&2
    exit 1
fi

if [[ ! -b "${DEV}" ]]; then
    echo "${DEV} is not a block device" >&2
    exit 1
fi
if [[ "$(lsblk -dno TYPE "${DEV}")" != disk ]]; then
    echo "${DEV} is not a whole disk (give the disk, not a partition)" >&2
    exit 1
fi
# Anything of the running system mounted from this disk means it is not an SD
# card we may erase.
while read -r mnt; do
    case "$mnt" in
        /|/boot|/boot/*|/home|/usr|/var|/nix|"[SWAP]")
            echo "REFUSING to touch ${DEV}: it holds the mounted system path '$mnt'" >&2
            exit 1
            ;;
    esac
done < <(lsblk -nro MOUNTPOINTS "${DEV}" 2>/dev/null || lsblk -nro MOUNTPOINT "${DEV}")

OUT="$SCAM_OUT"
for f in BOOT.BIN image.ub boot.scr rootfs.tar.gz; do
    if [[ ! -f "${OUT}/$f" ]]; then
        echo "ERROR: ${OUT}/$f missing. Run 'make sdcard' first." >&2
        exit 1
    fi
done

if [[ $EUID -ne 0 ]]; then
    echo "Partitioning needs root; re-running with sudo."
    exec sudo -- bash "${BASH_SOURCE[0]}" "$@"
fi

echo "About to ERASE and write to: ${DEV}"
lsblk "${DEV}" || true
echo
echo "Contents to be written:"
ls -lh "${OUT}/"
echo
read -r -p "Type 'yes' to continue: " ans
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
partprobe "${DEV}" 2>/dev/null || true
sleep 1

if [[ "${DEV}" =~ [0-9]$ ]]; then
    PART_BOOT="${DEV}p1"
    PART_ROOT="${DEV}p2"
else
    PART_BOOT="${DEV}1"
    PART_ROOT="${DEV}2"
fi

echo "==> mkfs BOOT (FAT32)"
mkfs.vfat -F 32 -n BOOT "${PART_BOOT}"

echo "==> mkfs rootfs (ext4)"
mkfs.ext4 -F -L rootfs "${PART_ROOT}"

echo "==> Mounting and copying"
MNT_BOOT=$(mktemp -d)
MNT_ROOT=$(mktemp -d)
cleanup() {
    umount "${MNT_BOOT}" 2>/dev/null || true
    umount "${MNT_ROOT}" 2>/dev/null || true
    rmdir "${MNT_BOOT}" "${MNT_ROOT}" 2>/dev/null || true
}
trap cleanup EXIT
mount "${PART_BOOT}" "${MNT_BOOT}"
mount "${PART_ROOT}" "${MNT_ROOT}"

cp -f "${OUT}/BOOT.BIN" "${OUT}/image.ub" "${OUT}/boot.scr" "${MNT_BOOT}/"
for bit in "${OUT}"/*.bit.bin; do
    [[ -f "$bit" ]] && cp -f "$bit" "${MNT_BOOT}/"
done

echo "==> Extracting rootfs"
tar -xzf "${OUT}/rootfs.tar.gz" -C "${MNT_ROOT}"

sync
echo
echo "==> Done. SD card ${DEV} is ready."
