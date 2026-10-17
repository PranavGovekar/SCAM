# TDC Application

An independent Vivado project cloned from the editable base Vivado project.
It preserves the base PS/PL contract and adds:

- 2x LVDS inputs from the FMC DIO card, plus a calibration input
- 3x `diff_to_se_1ch`
- `tdc_top`
- Per-channel XPM asynchronous FIFOs inside `tdc_channel`: one for physics
  hits, one for calibration hits
- LED routing (heartbeat, capture active, input monitor)

The two inputs are FMC DIO 5ch channels 0 and 1 on ZCU102 HPC0 (card
comparator outputs on LA33 and LA20). All five card outputs are kept disabled
(`oe` = 1) with 50 ohm input termination on (`term` = 1). HPC1 is not used.
The input threshold is the card's DAC: set it before taking data
(`sudo threshold <mV>`); it powers up at 0 V.

| LED | Shows |
| :-- | :-- |
| GPIO_LED_3 (AJ14) | channel 0 input, on while above threshold |
| GPIO_LED_4 (AJ15) | channel 1 input |
| card LED_TOP | heartbeat |

## Calibration input

FMC DIO card channel 2 (LA16, pins Y12/AA12) is the calibration input: connect
a free-running square wave there (e.g. a bench generator near 100 MHz). Its
threshold is the same DAC setting as the other channels.

When the program sets `axi_gpio_config` bit 0, `tdc_top`:

1. disables both channels for 64 clk_fast cycles (delay lines held in reset;
   the coarse counter keeps running),
2. switches the input mux of both channels to the calibration input 16 cycles
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
