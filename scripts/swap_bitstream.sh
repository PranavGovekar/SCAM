#!/usr/bin/env bash
set -euo pipefail

# Runtime bitstream swap helper, to be run on the ZCU102 itself.
# Usage: swap_bitstream.sh <tdc|coincidence>

which="${1:-}"
case "${which}" in
    tdc|coincidence)
        sudo fpgautil -b "/lib/firmware/${which}.bit.bin"
        ;;
    *)
        echo "Usage: $0 <tdc|coincidence>"
        exit 1
        ;;
esac
