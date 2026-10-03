#!/usr/bin/env bash
set -euo pipefail

# Build helper for hardware.
# Usage: build_hw.sh <base|tdc|ct>

target="${1:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
case "${target}" in
    base)
        # hw/base/system.xsa is the one canonical XSA. Do not copy it into
        # petalinux/project-spec/hw-description/: petalinux-config empties that
        # directory before it copies the XSA in, so a copy there is deleted on
        # the very next config run.
        echo "==> Building base XSA"
        pushd hw/base > /dev/null
        bash "$repo_root/scripts/run_vivado.sh" -mode batch -source build_base_xsa.tcl
        popd > /dev/null
        if [[ ! -f hw/base/system.xsa ]]; then
            echo "!! Vivado did not produce hw/base/system.xsa" >&2
            echo "   The real error is in hw/base/vivado.log." >&2
            exit 1
        fi
        echo "==> Base XSA ready: hw/base/system.xsa"
        echo "    Next: make petalinux-config"
        ;;
    tdc)
        echo "==> Building TDC bitstream"
        mkdir -p hw/tdc/bitstream
        pushd hw/tdc > /dev/null
        bash "$repo_root/scripts/run_vivado.sh" -mode batch -source build_tdc.tcl
        if [[ -f bitstream/tdc.bit ]]; then
            echo "all:{bitstream/tdc.bit}" > tdc.bif
            bootgen -image tdc.bif -arch zynqmp -o bitstream/tdc.bit.bin -w
            echo "==> hw/tdc/bitstream/tdc.bit.bin"
            echo "    Next: make petalinux"
        else
            echo "!! Vivado did not produce tdc.bit -- check build_tdc.tcl"
            exit 1
        fi
        popd > /dev/null
        ;;
    ct)
        echo "==> Building CT bitstream"
        mkdir -p hw/ct/bitstream
        pushd hw/ct > /dev/null
        bash "$repo_root/scripts/run_vivado.sh" -mode batch -source build_ct.tcl
        if [[ -f bitstream/coincidence.bit ]]; then
            echo "all:{bitstream/coincidence.bit}" > ct.bif
            bootgen -image ct.bif -arch zynqmp -o bitstream/coincidence.bit.bin -w
            echo "==> hw/ct/bitstream/coincidence.bit.bin"
            echo "    Next: make petalinux"
        else
            echo "!! Vivado did not produce coincidence.bit -- check build_ct.tcl"
            exit 1
        fi
        popd > /dev/null
        ;;
    *)
        echo "Usage: $0 <base|tdc|ct>"
        exit 1
        ;;
esac
