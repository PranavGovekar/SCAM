# Architecture

## Big picture

One Linux image. Two bitstreams. Bitstream swapped at runtime.

    +-----------------------------------------------------+
    |  Host PC                                            |
    |    collect_data.py  <-  UDP  <-  ZCU102             |
    +-----------------------------------------------------+
                          ^
                          | 1 GbE
                          v
    +-----------------------------------------------------+
    |  ZCU102                                             |
    |    PetaLinux (rootfs, kernel, apps)                 |
    |    PL bitstream: TDC  OR  CT  (swappable)           |
    +-----------------------------------------------------+

## Why no kernel drivers on PL

The userspace applications access PL registers through `/dev/mem`. There
are no UIO drivers, no PL-side device tree nodes, and no kernel module
bound to the AXI GPIOs or the AXI DMA. Consequences:

- Reconfiguring the PL does not disturb the kernel.
- `fpgautil` swaps bitstreams in ~50 ms without a reboot.
- No device tree overlays are required.

## PL contract

Any bitstream that drops into this Linux image must respect the AXI
footprint in `pl-contract.md`. TDC and CT both do. New applications
must too.

## Clock domains

    pl_clk0     100 MHz   AXI bus + control plane
    clk_wiz_0
      clk_out1  400 MHz   TDC fast clock
      clk_out2  200 MHz   CT fast clock

Both outputs come from one MMCM inside `clk_wiz_0`.

## Data flow

### TDC

    diff_in_0/1 -> diff_to_se -> hit_concat -> tdc_top -> axis_data_fifo
                                                       -> axi_dma_0 (S2MM)
                                                       -> DDR
    CPU reads DMA buffer, packetises 90 hits, sends UDP.

### CT

    diff_in_0..3 -> diff_to_se -> ct_top -> FIFO (512 x 64)
                                         -> exposed through AXI GPIO
    CPU polls flags GPIO, pops FIFO, packetises 1 event per packet,
    sends UDP.

## Reset and enable

Both applications expose the same control scheme on `axi_gpio_ctrl`:

    bit 0  en_i     active-high enable
    bit 1  reset    driven to proc_sys_reset.ext_reset_in (active-low assertion)

The C applications perform the same reset-and-wake sequence:
assert reset, clear, wake. See `sw/common/` for the sequence.
