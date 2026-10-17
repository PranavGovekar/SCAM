# PL Contract

Any bitstream running in the SCAM Linux image must satisfy this contract.

## Fixed AXI peripherals

| Address        | Peripheral         | Direction | Width | Notes |
|---------------:|:-------------------|:----------|:------|:------|
| `0xA0000000`   | `axi_dma_0`        | S2MM      | 128b  | Stream in only |
| `0xA0010000`   | `axi_gpio_ctrl`    | OUT       | 2     | bit0=en, bit1=rst |
| `0xA0020000`   | `axi_gpio_status`  | IN        | 32    | Application-defined |
| `0xA0030000`   | `axi_gpio_config`  | OUT       | 64    | Dual channel: 0x00 + 0x08 |
| `0xA0040000`   | `axi_gpio_status2` | IN        | 32    | Application-defined |
| `0xA0050000`   | `axi_gpio_flags`   | IN        | 32    | Application-defined |

## Fixed clocks

- `pl_clk0` from PS = 100 MHz -> AXI bus
- `clk_wiz_0/clk_out1` = 400 MHz -> TDC
- `clk_wiz_0/clk_out2` = 200 MHz -> CT

## Fixed interrupts

- `pl_ps_irq0` <- `axi_dma_0/s2mm_introut`

## Fixed memory

- `0x70000000`, 1 MiB of PS DDR is reserved in the device tree (`no-map`) as
  the AXI DMA destination buffer. `DMA_RAM_BASE` / `DMA_RAM_SIZE` in
  `sw/common/reg_io.h` name it. Point the DMA nowhere else: the rest of DDR
  belongs to Linux.

## Usage per application

### TDC

- `axi_dma_0`: used, S2MM path only
- `axi_gpio_ctrl`: used
- `axi_gpio_status[31:0]`: TDC overflow counter
- `axi_gpio_config`: tied to 0
- `axi_gpio_status2`: tied to 0
- `axi_gpio_flags`: tied to 0

### CT

- `axi_dma_0`: idle (input stream tied to a constant)
- `axi_gpio_ctrl`: used
- `axi_gpio_status[31:0]`: `fifo_dout[31:0]`
- `axi_gpio_config` ch1: `{delay_C[7:0], delay_B[7:0], delay_A[7:0], window_width[7:0]}`
- `axi_gpio_config` ch2: `{11'b0, pop_pulse, sel[3:0], pulse_width[7:0], delay_D[7:0]}`
- `axi_gpio_status2[31:0]`: `fifo_dout[63:32]`
- `axi_gpio_flags[1:0]`: `{fifo_empty, fifo_valid}`
- `axi_gpio_flags[2]`: pop acknowledge, toggles each time a pop has put a new
  event on `fifo_dout`
- `axi_gpio_flags[31:16]`: events dropped because the FIFO was full (stops at
  65535; cleared by reset or by dropping enable)

## Adding a new application

See `adding-an-app.md`. Your `hw/bd.tcl` edits a private copy of the base
block design. Do not add or remove AXI peripherals. Route your application's
signals through the existing GPIOs. Reuse `axi_gpio_config` bits as your own
register space, documenting the bit assignment in your application's
README.

The build enforces this contract: after an application's `bd.tcl` has run,
`hw/base/scam_app.tcl` checks the six addresses and ranges, the three clock
frequencies, and the DMA interrupt, and stops if any differs.

## What breaks the contract

- Adding a new AXI slave peripheral -> not described to the shared Linux
  image, and other applications cannot rely on it.
- Changing clock frequencies -> downstream timing assumptions break.
- Binding a kernel driver to a PL peripheral -> reconfiguration hangs the bus.
