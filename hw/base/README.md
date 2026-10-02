# Base Vivado Project

Generates `system.xsa` -- the hardware handoff used by PetaLinux.

Contains only the fixed PL contract peripherals (see `docs/pl-contract.md`).
No application IP.

## Build

    make base-xsa

The Vivado project is the editable template. Open
`hw/base/build/scam_base_project/scam_base.xpr` in Vivado, or recreate it by
running `make base-xsa`. The XSA is an export for PetaLinux, not the editable
Vivado project. `make base-xsa` copies it to
`petalinux/project-spec/hw-description/system.xsa`.

## Contents

- Zynq UltraScale+ PS (trimmed: DDR4, GEM3, UART0, SD1, QSPI, I2C1, GPIO)
- `ps8_0_axi_periph` AXI interconnect
- `axi_dma_0` (S2MM only, 128-bit)
- `axi_gpio_ctrl` (2-bit OUT)
- `axi_gpio_status` (32-bit IN)
- `axi_gpio_config` (dual, 32+32 OUT)
- `axi_gpio_status2` (32-bit IN)
- `axi_gpio_flags` (32-bit IN)
- `clk_wiz_0` (100 MHz in, 400 MHz + 200 MHz out)
- `proc_sys_reset_0`

Application build scripts use Vivado's project-save operation to clone this
template into their own project folders, then add application logic without
changing the six AXI addresses, DMA stream/interrupt, or PS clock setup. Saved
changes to this template are therefore inherited by later TDC/CT builds.
`make clean` keeps this template project. To recreate it from the checked-in
TCL sources and discard GUI edits, run `SCAM_REBUILD_TEMPLATE=1 make base-xsa`.
