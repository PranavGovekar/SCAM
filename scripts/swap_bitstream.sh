#!/usr/bin/env bash
set -euo pipefail

# Runtime bitstream swap helper, to be run on the ZCU102 itself.
# Usage: swap_bitstream.sh <name>     e.g. tdc, coincidence

which="${1:-}"
bit="/lib/firmware/${which}.bit.bin"
if [[ -z "${which}" || ! -f "${bit}" ]]; then
    echo "Usage: $0 <name>"
    echo "Available:"
    for f in /lib/firmware/*.bit.bin; do
        [[ -f "$f" ]] && echo "  $(basename "$f" .bit.bin)"
    done
    exit 1
fi
sudo fpgautil -b "${bit}"
