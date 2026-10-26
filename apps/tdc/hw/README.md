# TDC Application

An independent Vivado project cloned from the editable base Vivado project.
It preserves the base PS/PL contract and adds:

- 4x LVDS inputs from the FMC DIO card, plus a calibration input
- 5x `diff_to_se_1ch`
- `tdc_top`
- Per-channel XPM asynchronous FIFOs inside `tdc_channel`: one for physics
  hits, one for calibration hits
- LED routing (heartbeat, capture active, input monitor)

The four inputs are FMC DIO 5ch channels 0 to 3 on ZCU102 HPC0 (card
comparator outputs on LA33, LA20, LA16 and LA03). All five card outputs are kept disabled
(`oe` = 1) with 50 ohm input termination on (`term` = 1). HPC1 is not used.
The input threshold is the card's DAC: set it before taking data
(`sudo threshold <mV>`); it powers up at 0 V.

| LED | Shows |
| :-- | :-- |
| GPIO_LED_0..4 | running pattern while the TDC is enabled (control GPIO bit 0) |
| GPIO_LED_5 (AH13) | channel 0 input, on while above threshold |
| GPIO_LED_6 (AH14) | channel 1 input |
| GPIO_LED_7 (AL12) | channel 2 input (channel 3 has no LED) |
| card LED_TOP | heartbeat |

## Delay-line placement

Each channel has a start and a stop delay line, each in its own slice column.
`tdc.xdc` gives every line two pblocks, so it can only be placed one way: the
chain (100 CARRY8 and their capture flip-flops) in rows Y20..Y119, and the
launch flip-flop, with the channel's input mux in the start column, in rows
Y16..Y19 just below it. Both have `EXCLUDE_PLACEMENT`, so no other logic
goes into those rows.

| Channel | Start | Stop |
| :-- | :-- | :-- |
| 0 | X46 | X47 |
| 1 | X48 | X49 |
| 2 | X50 | X51 |
| 3 | X52 | X53 |

All eight are in clock region X1Y0/X1Y1. With one pblock of 120 rows per
line the placer chose differently from build to build, and sometimes put a
chain at Y0..Y99 with the launch flip-flop above it.

## End of a run (flush)

The arbiter in `tdc_top` sends packets of 90 words; the DMA only delivers a
packet once it is complete. At the end of a run the program disables the TDC
and sets `axi_gpio_config` bit 1. The arbiter then sends every word still in
a FIFO, and once all FIFOs are empty finishes the open packet with padding
words (`0xCF` in `[127:120]`, never taken for a hit). `axi_gpio_flags` bit 1
reports when every FIFO is empty and no packet is open. With bit 1 clear the
arbiter works as before.

## Calibration input

FMC DIO card channel 4 (LA00, pins Y4/Y3) is the calibration input: connect
a free-running square wave there (e.g. a bench generator near 100 MHz). Its
threshold is the same DAC setting as the other channels.

When the program sets `axi_gpio_config` bit 0, `tdc_top`:

1. disables all channels for 64 clk_fast cycles (delay lines held in reset;
   the coarse counter keeps running),
2. switches the input mux of every channel to the calibration input 16 cycles
   into that pause, so a glitch from the switch cannot become a hit,
3. re-enables the channels and sets `axi_gpio_flags` bit 0.

In calibration mode a channel writes its records to its calibration FIFO
(channel ID field `0x800` + channel, bit 127 set) and never to the physics
FIFO; hits already in the physics FIFOs are still read out. A full
calibration FIFO drops the hit and counts it in `axi_gpio_status2`. Clearing
bit 0 switches back the same way.

Only one generator pulse in 256 reaches the channels: a counter clocked by
the calibration input's falling edge opens a gate for one period. The channels
are then always re-armed long before the pulse arrives. Without the gate the
recorded phases are biased. A delay line is released on a clock edge, and the
pulse recorded is the first one after that release, so a pulse is picked as
often as clock edges fit in the low time before it: 2 or 3 at 97.3 MHz,
depending on its phase. Measured on the board: the tables were off by up to
140 ps and ToT RMS was 12 ps instead of 6 ps. (A random re-arm delay in whole
clock cycles does not help: the release stays on the clock grid.) At 97.3 MHz
the gate passes 380 k pulses per second per channel.

AXI footprint: unchanged from base. Register use: `docs/pl-contract.md`.

## Build

    make tdc-bitstream

Produces `build/apps/tdc/tdc.bit.bin`. The block-design edits are in `bd.tcl`.
