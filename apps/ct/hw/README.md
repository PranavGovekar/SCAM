# Coincidence Trigger Application

An independent Vivado project cloned from the editable base Vivado project.
It preserves the base PS/PL contract and adds:

- 4x LVDS inputs from the FMC DIO card
- 4x `diff_to_se_1ch`
- `ct_top` (glue + wrapper for `four_fold_coincidence`)

The four inputs (A to D) are FMC DIO 5ch channels 0–3 on ZCU102 HPC0. The
fifth card channel is unused, and HPC1 is not used. The card outputs are kept
disabled. Set the input threshold before taking data (`sudo threshold <mV>`);
it powers up at 0 V.

| LED | Shows |
| :-- | :-- |
| GPIO_LED_3 (AJ14) | input A (channel 0), on while above threshold |
| GPIO_LED_4 (AJ15) | input B (channel 1) |
| GPIO_LED_5 (AH13) | input C (channel 2) |
| GPIO_LED_6 (AH14) | input D (channel 3) |

AXI footprint: unchanged from base. All configuration goes through
`axi_gpio_config`, all readout through `axi_gpio_status` /
`axi_gpio_status2` / `axi_gpio_flags`.

## Build

    make ct-bitstream

Produces `build/apps/ct/ct.bit.bin`. The block-design edits are in `bd.tcl`.

## GPIO assignments

See `docs/pl-contract.md` for the register map.
