# sw/tdc

TDC userspace readout. Reads 1440-byte packets (90 hits × 16 bytes) from
the AXI DMA S2MM path and streams them over UDP.

## Build

    make            # uses aarch64-xilinx-linux-gcc by default
    make CC=gcc     # native build for testing

## Run

    sudo ./yeet-data-tdc -n 18000 192.168.1.100
    sudo ./yeet-data-tdc -t 60 -v 1000 192.168.1.100

Flags:

- `-n N`  — stop after N hits (rounded up to a multiple of 90)
- `-t S`  — stop after S seconds
- `-v MV` — configure the I2C DAC threshold to MV millivolts first

## Register map

| Address | Used for |
| :-- | :-- |
| `0xA0000000` | AXI DMA (S2MM) |
| `0xA0010000` | Control GPIO: bit0=enable, bit1=reset |
| `0xA0020000` | Status GPIO: FIFO overflow counter |

See `../../docs/pl-contract.md` for the full table.
