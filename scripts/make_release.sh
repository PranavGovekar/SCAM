#!/usr/bin/env bash
set -euo pipefail

# Collect release artifacts into out/release/:
#   scam-zcu102-<version>.wic.xz       single SD card image (dd / balenaEtcher)
#   scam-zcu102-<version>-boot.tar.gz  boot files + rootfs for scripts/flash_sd.sh
#   scam-zcu102-<version>-sdk.sh       cross toolchain for building applications
#   SHA256SUMS
# Prerequisites: make sdcard sdk

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

version="${SCAM_VERSION:-$(git -C "$SCAM_ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}"
name="scam-zcu102-$version"
rel="$SCAM_OUT/release"
wic="$SCAM_IMAGES_DIR/petalinux-sdimage.wic"
sdk="$SCAM_IMAGES_DIR/sdk.sh"

missing=0
for f in "$wic" "$sdk" "$SCAM_OUT/BOOT.BIN" "$SCAM_OUT/image.ub" "$SCAM_OUT/boot.scr" "$SCAM_OUT/rootfs.tar.gz"; do
    if [[ ! -f "$f" ]]; then
        echo "missing: ${f#"$SCAM_ROOT"/}" >&2
        missing=1
    fi
done
if [[ $missing -eq 1 ]]; then
    echo "Run: make sdcard sdk" >&2
    exit 1
fi

rm -rf "$rel"
mkdir -p "$rel"

echo "==> $name.wic.xz"
xz -T0 -c "$wic" > "$rel/$name.wic.xz"

echo "==> $name-boot.tar.gz"
boot_files=(BOOT.BIN image.ub boot.scr rootfs.tar.gz)
for bit in "$SCAM_OUT"/*.bit.bin; do
    [[ -f "$bit" ]] && boot_files+=("$(basename "$bit")")
done
tar -C "$SCAM_OUT" -czf "$rel/$name-boot.tar.gz" "${boot_files[@]}"

echo "==> $name-sdk.sh"
cp -f "$sdk" "$rel/$name-sdk.sh"
chmod +x "$rel/$name-sdk.sh"

(cd "$rel" && sha256sum -- * > SHA256SUMS)

echo
echo "Release artifacts in ${rel#"$SCAM_ROOT"/}/:"
ls -lh "$rel/"
