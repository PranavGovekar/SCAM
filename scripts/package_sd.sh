#!/usr/bin/env bash
set -euo pipefail

# Assemble SD card artifacts into ./out/
# Prerequisites: 'make petalinux' built the image and the 'package' action
# created BOOT.BIN (make sdcard does both in order).

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

img="$SCAM_IMAGES_DIR"
out="$SCAM_OUT"

missing=0
for f in BOOT.BIN image.ub boot.scr rootfs.tar.gz; do
    if [[ ! -f "$img/$f" ]]; then
        echo "missing: ${img#"$SCAM_ROOT"/}/$f" >&2
        missing=1
    fi
done
if [[ $missing -eq 1 ]]; then
    echo "The PetaLinux image is incomplete. Run: make petalinux, then make sdcard" >&2
    exit 1
fi

mkdir -p "$out"
echo "==> Collecting PetaLinux artifacts"
for f in BOOT.BIN image.ub boot.scr rootfs.tar.gz; do
    cp -f "$img/$f" "$out/"
done

# The bitstreams the image installs are already inside the rootfs. Copies go
# next to the boot files for convenience.
echo "==> Copying bitstreams"
rm -f "$out"/*.bit.bin
for bit in "$SCAM_RECIPES"/recipes-bsp/fpga-bitstreams/files/*.bit.bin; do
    [[ -f "$bit" ]] && cp -f "$bit" "$out/"
done

echo
echo "SD card contents in ${out#"$SCAM_ROOT"/}/:"
ls -lh "$out/"
