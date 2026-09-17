# sw/ct

Coincidence trigger userspace readout. Polls the CT FIFO (512 × 64-bit,
exposed through AXI GPIO) and streams one event per UDP packet.

## Build

    make            # uses aarch64-xilinx-linux-gcc by default
    make CC=gcc     # native build for testing

## Run

    sudo ./yeet-data-ct -n 18000 192.168.1.100
    sudo ./yeet-data-ct -t 60 -v 1000 192.168.1.100

Flags:

- `-n N`  — stop after N events
- `-t S`  — stop after S seconds
- `-v MV` — configure the I2C DAC threshold to MV millivolts first

## Register map

| Address | Used for |
| :-- | :-- |
| `0xA0010000` | Control GPIO: bit0=enable, bit1=reset |
| `0xA0020000` | `fifo_dout[31:0]` |
| `0xA0030000` | Config (ch1) + config (ch2) — window, delays, pulse, sel, pop |
| `0xA0040000` | `fifo_dout[63:32]` |
| `0xA0050000` | Flags: bit0=valid, bit1=empty |

See `../../docs/pl-contract.md` for the full table and bit assignments.
