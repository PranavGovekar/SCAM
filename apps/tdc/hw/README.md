# TDC Application

An independent Vivado project cloned from the editable base Vivado project.
It preserves the base PS/PL contract and adds:

- 2x LVDS inputs from the FMC DIO card
- 2x `diff_to_se_1ch`
- `tdc_top`
- Per-channel XPM asynchronous FIFOs inside `tdc_channel`
- LED routing (heartbeat, capture active, input monitor)

The two inputs are FMC DIO 5ch channels 0 and 1 on ZCU102 HPC0 (card
comparator outputs on LA33 and LA20). All five card outputs are kept disabled
(`oe` = 1) with 50 ohm input termination on (`term` = 1). HPC1 is not used.
The input threshold is the card's DAC: set it before taking data
(`sudo threshold <mV>`); it powers up at 0 V.

| LED | Shows |
| :-- | :-- |
| GPIO_LED_3 (AJ14) | channel 0 input, on while above threshold |
| GPIO_LED_4 (AJ15) | channel 1 input |
| card LED_TOP | heartbeat |

AXI footprint: unchanged from base.

## Build

    make tdc-bitstream

Produces `build/apps/tdc/tdc.bit.bin`. The block-design edits are in `bd.tcl`.
