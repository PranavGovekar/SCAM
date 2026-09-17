# Base Vivado Project

Generates `system.xsa` -- the base design used by PetaLinux.

Contains only the fixed PL contract peripherals (see `docs/pl-contract.md`).
No application IP.

## Build

    make base-xsa

The resulting XSA is written directly to
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
