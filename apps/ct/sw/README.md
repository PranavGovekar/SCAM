# apps/ct/sw

Coincidence trigger userspace readout. Polls the CT FIFO (512 × 64-bit,
exposed through AXI GPIO) and streams one event per UDP packet.

## Build

    make app-ct SCAM_SDK=<installed sdk>   # from the repository root
    make CC=gcc                             # here: native build for testing

The binary is written to `build/apps/ct/yeet-data-ct`.

## Run

    sudo ./yeet-data-ct -n 18000 192.168.1.100
    sudo ./yeet-data-ct -t 60 -v 1000 192.168.1.100

Flags:

- `-n N`  — stop after N events (`-1` = no limit)
- `-t S`  — stop after S seconds (`-1` = no limit)
- `-v MV` — configure the I2C DAC threshold to MV millivolts first

With no limit the program runs until Ctrl+C. At the end it prints how many
events were sent and how many the hardware dropped because its FIFO was full.

## Register map

| Address | Used for |
| :-- | :-- |
| `0xA0010000` | Control GPIO: bit0=enable, bit1=reset |
| `0xA0020000` | `fifo_dout[31:0]` |
| `0xA0030000` | Config (ch1) + config (ch2) — window, delays, pulse, sel, pop |
| `0xA0040000` | `fifo_dout[63:32]` |
| `0xA0050000` | Flags: bit0=valid, bit1=empty, bit2=pop acknowledge, [31:16]=dropped events |

See `../../../docs/pl-contract.md` for the full table and bit assignments.
