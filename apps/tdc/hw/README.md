# TDC Application

An independent Vivado project cloned from the editable base Vivado project.
It preserves the base PS/PL contract and adds:

- 2x differential input pairs (SMA)
- 2x `diff_to_se_1ch`
- `tdc_top`
- Per-channel XPM asynchronous FIFOs inside `tdc_channel`
- LED routing (heartbeat, capture active)

The two inputs use FMC DIO 5ch channels 0 and 1 on ZCU102 HPC0. The other
HPC0 channel pins are reserved for application variants; HPC1 is not used.

AXI footprint: unchanged from base.

## Build

    make tdc-bitstream

Produces `build/apps/tdc/tdc.bit.bin`. The block-design edits are in `bd.tcl`.
