#!/usr/bin/env bash
set -euo pipefail

# Build helper for hardware.
# Usage: build_hw.sh <base|tdc|ct>

target="${1:-}"
case "${target}" in
    base)
        echo "==> Building base XSA"
        pushd hw/base > /dev/null
        vivado -mode batch -source build_base_xsa.tcl
        mkdir -p ../../petalinux/project-spec/hw-description
        cp -f base.xsa ../../petalinux/project-spec/hw-description/system.xsa
        echo "==> system.xsa placed in petalinux/project-spec/hw-description/"
        popd > /dev/null
        ;;
    tdc)
        echo "==> Building TDC bitstream"
        mkdir -p hw/tdc/bitstream
        pushd hw/tdc > /dev/null
        vivado -mode batch -source build_tdc.tcl
        if [[ -f bitstream/tdc.bit ]]; then
            echo "all:{bitstream/tdc.bit}" > tdc.bif
            bootgen -image tdc.bif -arch zynqmp -o bitstream/tdc.bit.bin -w
            echo "==> hw/tdc/bitstream/tdc.bit.bin"
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
        vivado -mode batch -source build_ct.tcl
        if [[ -f bitstream/coincidence.bit ]]; then
            echo "all:{bitstream/coincidence.bit}" > ct.bif
            bootgen -image ct.bif -arch zynqmp -o bitstream/coincidence.bit.bin -w
            echo "==> hw/ct/bitstream/coincidence.bit.bin"
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
