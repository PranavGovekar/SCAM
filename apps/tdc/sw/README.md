# apps/tdc/sw

TDC userspace readout. Reads 1440-byte packets (90 hits × 16 bytes) from
the AXI DMA S2MM path and streams them over UDP.

## Build

    make app-tdc SCAM_SDK=<installed sdk>   # from the repository root
    make CC=gcc                             # here: native build for testing

The binary is written to `build/apps/tdc/yeet-data-tdc`.

## Run

    sudo ./yeet-data-tdc -n 18000 192.168.1.100
    sudo ./yeet-data-tdc -t 60 -v 1000 192.168.1.100
    sudo ./yeet-data-tdc -t 600 -v 250 -c 1 -C 60 192.168.1.100   # calibrate every minute

Flags:

- `-n N`  — stop after N hits (rounded up to a multiple of 90; `-1` = no limit)
- `-t S`  — stop after S seconds (`-1` = no limit)
- `-v MV` — configure the I2C DAC threshold to MV millivolts first
- `-c S`  — calibrate for S seconds at the start (default: no calibration)
- `-C S`  — calibrate again every S seconds (needs `-c`)

## Calibration

The calibration input (FMC DIO card channel 2, see `../hw/README.md`) needs a
free-running square wave. During a window the program reads the calibration
records through the DMA like hits, counts the fine codes of each delay line
(ch0 start, ch0 stop, ch1 start, ch1 stop), and afterwards sends one
code-density table per line, then carries on with physics. Physics hits still
in the FIFOs are sent as usual during the window; new ones are not recorded.
Records that arrive after the window has closed are discarded: which ones are
lost does not depend on their phase, so the tables are not biased.

The firmware passes one generator pulse in 256 (see `../hw/README.md`), about
0.3 million records per line per second at 97.3 MHz. A 1 s window calibrates
ToT well (its RMS settles from about 15000 hits); for each line right to 1 ps
(about 1 million hits) take 4 s.

The board prints one line per delay line, e.g.

    [cal 0] ch0 start: 412345 hits, codes 1..663, 0 empty, 0 wide, flags 0x000

## UDP packets

Every packet is 1440 bytes: 90 words of 128 bits, least significant byte
first. A physics packet holds 90 hits, unchanged from the firmware
(`parse_tdc` in `sw/host/collect_data.py`; bit 127 is always 0). A calibration
packet holds calibration words, bit 127 set, `[127:120]` giving the kind:

| `[127:120]` | Word | Fields |
| :-- | :-- | :-- |
| `0xC1` | line header | `[119:112]` calibration id (counts up, wraps at 256), `[111:108]` line (0 ch0 start, 1 ch0 stop, 2 ch1 start, 3 ch1 stop), `[107:96]` flags, `[95:64]` hits, `[63:54]` first code, `[53:44]` last code, `[43:34]` empty codes, `[33:24]` wide codes, `[23:16]` table words that follow, `[15:0]` window in ms |
| `0xC2` | table | `[119:112]` calibration id, `[111:108]` line, `[107:98]` first code, `[95:0]` six u16, the bin-centre time of that code and the next five, in 1/16 ps |
| `0xCF` | padding | fills the last calibration packet |

Each line is a header word followed by its table words, the four lines one
after the other, in 5 or 6 packets. The table is
`t(k) = 2500 ps * (n_first + ... + n_(k-1) + n_k / 2) / N`, as `test_tdc.py`
computes it. Flags: `0x001` fewer than 50 hits per code, `0x002` more than
10 % of the codes empty, `0x004` a bin wider than 16 times the mean,
`0x008` fewer than 400 codes or the edge reached the last tap (784),
`0x010` calibration hits dropped because the FIFO was full (information only).

## Register map

| Address | Used for |
| :-- | :-- |
| `0xA0000000` | AXI DMA (S2MM) |
| `0xA0010000` | Control GPIO: bit0=enable, bit1=reset |
| `0xA0020000` | Status GPIO: FIFO overflow counter |
| `0xA0030000` | Config GPIO: bit 0 = calibration request |
| `0xA0040000` | Status2 GPIO: calibration hits dropped |
| `0xA0050000` | Flags GPIO: bit 0 = calibration mode in effect |

See `../../../docs/pl-contract.md` for the full table.
