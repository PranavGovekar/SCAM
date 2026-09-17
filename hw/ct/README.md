# Coincidence Trigger Application

Layers on top of the base block design. Adds:

- 4x differential input pairs (SMA)
- 4x `diff_to_se_1ch`
- `ct_top` (glue + wrapper for `four_fold_coincidence`)
- LED routing

AXI footprint: unchanged from base. All configuration goes through
`axi_gpio_config`, all readout through `axi_gpio_status` /
`axi_gpio_status2` / `axi_gpio_flags`.

## Build

    make ct

Produces `hw/ct/bitstream/coincidence.bit.bin`.

## GPIO assignments

See `docs/pl-contract.md` for the register map.
