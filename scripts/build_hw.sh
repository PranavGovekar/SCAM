#!/usr/bin/env bash
set -euo pipefail

# Build helper for hardware.
# Usage: build_hw.sh <base|app-name>

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

target="${1:-}"
if [[ -z "$target" ]]; then
    echo "Usage: $0 <base|app-name>" >&2
    exit 2
fi

if [[ "$target" == base ]]; then
    # hw/base/system.xsa is the one canonical XSA. Do not copy it into
    # petalinux/project-spec/hw-description/: petalinux-config empties that
    # directory before it copies the XSA in, so a copy there is deleted on
    # the very next config run.
    echo "==> Building base XSA"
    log_dir="$SCAM_ROOT/hw/base/build"
    mkdir -p "$log_dir"
    rm -f "$SCAM_ROOT/hw/base/system.xsa"
    cd "$log_dir"
    bash "$SCAM_ROOT/scripts/run_vivado.sh" -mode batch \
        -log "$log_dir/vivado.log" -journal "$log_dir/vivado.jou" \
        -source "$SCAM_ROOT/hw/base/build_base_xsa.tcl" || true
    if [[ ! -f "$SCAM_ROOT/hw/base/system.xsa" ]]; then
        echo "!! Vivado did not produce hw/base/system.xsa" >&2
        echo "   The real error is in hw/base/build/vivado.log." >&2
        exit 1
    fi
    echo "==> Base XSA ready: hw/base/system.xsa"
    exit 0
fi

apps="$SCAM_ROOT/scripts/apps.sh"
app_dir="$(bash "$apps" dir "$target")"
if [[ "$(bash "$apps" get "$target" has_hw)" != 1 ]]; then
    echo "Application '$target' has no hardware (expected $app_dir/hw/bd.tcl)." >&2
    exit 1
fi
if ! command -v bootgen >/dev/null 2>&1 && [[ -z "${VIVADO_SETTINGS:-}" ]]; then
    echo "bootgen not found on PATH. It ships with Vivado/Vitis; set VIVADO_SETTINGS" >&2
    echo "or source settings64.sh first." >&2
    exit 1
fi

bit_bin="$(bash "$apps" bitpath "$target")"
out_dir="$(dirname "$bit_bin")"
# Build under a temporary name and replace the previous bitstream only on
# success, so a failed build (for example a license problem) loses nothing.
bit="$out_dir/new.bit"
new_bin="$out_dir/new.bit.bin"
mkdir -p "$out_dir"
rm -f "$bit" "$new_bin"

echo "==> Building '$target' bitstream"
cd "$out_dir"
SCAM_APP_NAME="$target" \
SCAM_APP_HW_DIR="$app_dir/hw" \
SCAM_APP_BUILD_DIR="$out_dir/vivado" \
SCAM_BITSTREAM_OUT="$bit" \
    bash "$SCAM_ROOT/scripts/run_vivado.sh" -mode batch \
        -log "$out_dir/vivado.log" -journal "$out_dir/vivado.jou" \
        -source "$SCAM_ROOT/hw/base/scam_app.tcl" || true
if [[ ! -f "$bit" ]]; then
    echo "!! Vivado did not produce a bitstream for '$target'." >&2
    echo "   The real error is in ${out_dir#"$SCAM_ROOT"/}/vivado.log:" >&2
    grep -E '^ERROR' "$out_dir/vivado.log" 2>/dev/null | head -n 10 >&2 || true
    exit 1
fi

# fpgautil loads the bootgen .bit.bin format, not the raw Vivado .bit.
echo "all:{$bit}" > "$out_dir/bitstream.bif"
(
    if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
        set +u
        # shellcheck disable=SC1090
        source "$VIVADO_SETTINGS"
        set -u
    fi
    bootgen -image "$out_dir/bitstream.bif" -arch zynqmp -o "$new_bin" -w
)
if [[ ! -f "$new_bin" ]]; then
    echo "!! bootgen did not produce a .bit.bin for '$target'" >&2
    exit 1
fi
mv -f "$bit" "${bit_bin%.bin}"
mv -f "$new_bin" "$bit_bin"
echo "==> ${bit_bin#"$SCAM_ROOT"/}"
