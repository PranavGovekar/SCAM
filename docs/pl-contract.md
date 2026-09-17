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

## Adding a new application

Create a new Vivado project that layers on top of the base block design.
Do not add or remove AXI peripherals. Route your application's signals
through the existing GPIOs. Reuse `axi_gpio_config` bits as your own
register space, documenting the bit assignment in your application's
README.

## What breaks the contract

- Adding a new AXI slave peripheral -> DT mismatch, kernel probe failure.
- Changing clock frequencies -> downstream timing assumptions break.
- Binding a kernel driver to a PL peripheral -> reconfiguration hangs the bus.
