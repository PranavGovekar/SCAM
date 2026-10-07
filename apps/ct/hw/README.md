# Coincidence Trigger Application

An independent Vivado project cloned from the editable base Vivado project.
It preserves the base PS/PL contract and adds:

- 4x differential input pairs (SMA)
- 4x `diff_to_se_1ch`
- `ct_top` (glue + wrapper for `four_fold_coincidence`)

The four differential inputs use FMC DIO 5ch channels 0–3 on ZCU102 HPC0.
The remaining HPC0 input is unused, and HPC1 is not used.

AXI footprint: unchanged from base. All configuration goes through
`axi_gpio_config`, all readout through `axi_gpio_status` /
`axi_gpio_status2` / `axi_gpio_flags`.

## Build

    make ct-bitstream

Produces `build/apps/ct/coincidence.bit.bin`. The block-design edits are in `bd.tcl`.

## GPIO assignments

See `docs/pl-contract.md` for the register map.
