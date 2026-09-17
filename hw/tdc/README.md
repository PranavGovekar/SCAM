# TDC Application

Layers on top of the base block design. Adds:

- 2x differential input pairs (SMA)
- 2x `diff_to_se_1ch`
- `hit_concat`
- `tdc_top`
- `axis_data_fifo` (2048 x 128)
- LED routing (heartbeat, capture active)

AXI footprint: unchanged from base.

## Build

    make tdc

Produces `hw/tdc/bitstream/tdc.bit.bin`.
