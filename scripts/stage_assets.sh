#!/usr/bin/env bash
set -euo pipefail

# Stage the generated inputs that the PetaLinux recipes need:
#   * sw/common/*.c,*.h          -> recipes-apps/yeet-data-common/files/
#   * <app>/sw/*.c,*.h           -> recipes-apps/<binary>/files/
#   * build/apps/<app>/*.bit.bin -> recipes-bsp/fpga-bitstreams/files/
#
# Only applications that are baked into the image are staged: an application's
# sources are staged when a recipe directory recipes-apps/<binary>/ exists, and
# its bitstream when fpga-bitstreams.bb lists it. See docs/adding-an-app.md.
#
# Everything staged is generated output. apps/ and sw/ hold the real sources.
#
# Usage: stage_assets.sh <sources|bitstreams|both> [--require-bitstreams]

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

apps="$SCAM_ROOT/scripts/apps.sh"
bits_recipe="$SCAM_RECIPES/recipes-bsp/fpga-bitstreams/fpga-bitstreams.bb"
bits_dir="$SCAM_RECIPES/recipes-bsp/fpga-bitstreams/files"

what="${1:-both}"
require_bits=0
[[ "${2:-}" == "--require-bitstreams" ]] && require_bits=1

stage_dir() {
    local src_dir="$1" dst_dir="$2" f
    mkdir -p "$dst_dir"
    for f in "$src_dir"/*.c "$src_dir"/*.h; do
        [[ -f "$f" ]] || continue
        copy_if_changed "$f" "$dst_dir/$(basename "$f")"
    done
}

stage_sources() {
    local name binary
    stage_dir "$SCAM_ROOT/sw/common" "$SCAM_RECIPES/recipes-apps/yeet-data-common/files"
    for name in $(bash "$apps" list); do
        binary="$(bash "$apps" get "$name" binary)"
        [[ -d "$SCAM_RECIPES/recipes-apps/$binary" ]] || continue
        stage_dir "$(bash "$apps" dir "$name")/sw" "$SCAM_RECIPES/recipes-apps/$binary/files"
    done
}

stage_bitstreams() {
    local name bit src missing=0
    mkdir -p "$bits_dir"
    for name in $(bash "$apps" list); do
        bit="$(bash "$apps" get "$name" bitstream).bit.bin"
        grep -q "file://$bit\b" "$bits_recipe" || continue
        src="$(bash "$apps" bitpath "$name")"
        if [[ ! -f "$src" ]]; then
            echo "    missing bitstream: ${src#"$SCAM_ROOT"/}  (run: make $name-bitstream)" >&2
            missing=1
            continue
        fi
        copy_if_changed "$src" "$bits_dir/$bit"
    done
    if [[ $missing -eq 1 && $require_bits -eq 1 ]]; then
        echo "A bitstream that the image installs is missing. Run: make bitstreams" >&2
        exit 1
    fi
}

case "$what" in
    sources) stage_sources ;;
    bitstreams) stage_bitstreams ;;
    both) stage_sources; stage_bitstreams ;;
    *) echo "Usage: $0 <sources|bitstreams|both> [--require-bitstreams]" >&2; exit 2 ;;
esac
