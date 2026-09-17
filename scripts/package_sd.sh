#!/usr/bin/env bash
set -euo pipefail

# Assemble SD card artifacts into ./out/
# Prerequisites: 'make petalinux' has produced images.

OUT=out
mkdir -p "${OUT}"

echo "==> Collecting PetaLinux artifacts"
PL_IMG_DIR=petalinux/images/linux

cp -f "${PL_IMG_DIR}/BOOT.BIN"       "${OUT}/" || true
cp -f "${PL_IMG_DIR}/image.ub"       "${OUT}/" || true
cp -f "${PL_IMG_DIR}/system.dtb"     "${OUT}/" || true

# Rootfs: PetaLinux produces rootfs.tar.gz in the same dir
if [[ -f "${PL_IMG_DIR}/rootfs.tar.gz" ]]; then
    cp -f "${PL_IMG_DIR}/rootfs.tar.gz" "${OUT}/"
elif [[ -f "${PL_IMG_DIR}/rootfs.ext4" ]]; then
    cp -f "${PL_IMG_DIR}/rootfs.ext4" "${OUT}/"
else
    echo "WARN: no rootfs found in ${PL_IMG_DIR}"
fi

echo "==> Copying bitstreams"
[[ -f hw/tdc/bitstream/tdc.bit.bin ]] && \
    cp -f hw/tdc/bitstream/tdc.bit.bin "${OUT}/" || echo "WARN: tdc.bit.bin missing"
[[ -f hw/ct/bitstream/coincidence.bit.bin ]] && \
    cp -f hw/ct/bitstream/coincidence.bit.bin "${OUT}/" || \
    echo "WARN: coincidence.bit.bin missing"

echo
echo "SD card contents in ${OUT}/:"
ls -lh "${OUT}/"
