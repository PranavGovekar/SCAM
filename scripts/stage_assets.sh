#!/usr/bin/env bash
set -euo pipefail

# Stage the generated inputs that PetaLinux recipes need:
#   * C sources copied from sw/ into each recipe's files/ folder
#   * .bit.bin bitstreams copied into the fpga-bitstreams recipe
#
# Everything here is generated output. sw/ and hw/ hold the real sources.
#
# Usage: stage_assets.sh <sources|bitstreams|both> [--require-bitstreams]

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
recipes="$repo_root/petalinux/project-spec/meta-user"
bits_dir="$recipes/recipes-bsp/fpga-bitstreams/files"
base_xsa="$repo_root/hw/base/system.xsa"
tdc_bit="$repo_root/hw/tdc/bitstream/tdc.bit.bin"
ct_bit="$repo_root/hw/ct/bitstream/coincidence.bit.bin"

what="${1:-both}"
require_bits=0
[[ "${2:-}" == "--require-bitstreams" ]] && require_bits=1

# Copy only when the destination is missing or its content differs. This keeps
# mtimes stable so BitBake does not recompile unchanged recipes.
copy_if_changed() {
    local src="$1" dst="$2"
    [[ -f "$src" ]] || return 0
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        return 0
    fi
    cp -f "$src" "$dst"
    echo "    staged $(basename "$dst")"
}

stage_sources() {
    local name src_dir dst_dir f
    for name in common tdc ct; do
        src_dir="$repo_root/sw/$name"
        dst_dir="$recipes/recipes-apps/yeet-data-$name/files"
        [[ -d "$src_dir" ]] || continue
        mkdir -p "$dst_dir"
        for f in "$src_dir"/*.c "$src_dir"/*.h; do
            [[ -f "$f" ]] || continue
            copy_if_changed "$f" "$dst_dir/$(basename "$f")"
        done
    done
}

stage_bitstreams() {
    mkdir -p "$bits_dir"
    if [[ ! -f "$tdc_bit" || ! -f "$ct_bit" ]]; then
        if [[ $require_bits -eq 1 ]]; then
            echo "A bitstream is missing. Run: make bitstreams" >&2
            [[ -f "$tdc_bit" ]] || echo "  missing: hw/tdc/bitstream/tdc.bit.bin" >&2
            [[ -f "$ct_bit" ]] || echo "  missing: hw/ct/bitstream/coincidence.bit.bin" >&2
            exit 1
        fi
        echo "    note: a bitstream is missing, skipping it. Run: make bitstreams"
        return 0
    fi
    copy_if_changed "$tdc_bit" "$bits_dir/tdc.bit.bin"
    copy_if_changed "$ct_bit" "$bits_dir/coincidence.bit.bin"
}

case "$what" in
    sources) stage_sources ;;
    bitstreams) stage_bitstreams ;;
    both) stage_sources; stage_bitstreams ;;
    *) echo "Usage: $0 <sources|bitstreams|both> [--require-bitstreams]" >&2; exit 2 ;;
esac