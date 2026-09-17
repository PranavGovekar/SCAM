# SCAM

### <u>**S**</u>o, <u>**C**</u>an <u>**A**</u>nyone <u>**M**</u>ake-this-work?

Modular FPGA + PetaLinux platform for physics DAQ on the **Xilinx ZCU102**
(Zynq UltraScale+ XCZU9EG). Two application bitstreams share one Linux
image:

- **TDC** — 2-channel time-to-digital converter, DMA readout to DDR
- **CT**  — 4-channel multifold coincidence trigger, timestamped FIFO

The Linux image, rootfs, and device tree are identical for both.
Bitstreams are swapped at runtime with `fpgautil`; userspace code talks to
PL registers through `/dev/mem`. No kernel drivers are bound to PL
peripherals, so no reboot is needed to switch applications.

## Hardware

- Board: ZCU102 rev 1.0
- Part: `xczu9eg-ffvb1156-2-e`
- Vivado: 2023.2 or newer
- PetaLinux: 2023.2 or newer
- Ethernet: PS GEM3 (MIO 64..77), 1 GbE
- Host PC connects over the same network, receives UDP on port 8080

## Layout

    hw/base         Base Vivado project (PS + interconnect + GPIOs + DMA)
    hw/tdc          TDC application (VHDL + TCL on top of base)
    hw/ct           Coincidence trigger application (VHDL + TCL on top of base)
    sw/common       Shared C headers and helpers (reg_io, udp, i2c_dac, args)
    sw/tdc          TDC userspace application
    sw/ct           CT userspace application
    sw/host         Python UDP collector (runs on the host PC)
    petalinux       PetaLinux project skeleton
    scripts         Build, package, flash helpers
    docs            Architecture, contract, build guide, test plan

## Build

Requires Vivado 2023.2+ and PetaLinux 2023.2+ on a Linux host.

    make base-xsa        # generate base XSA, place in petalinux hw-description
    make bitstreams      # generate tdc.bit.bin + coincidence.bit.bin
    make petalinux-config
    make petalinux       # build the Linux image
    make sdcard          # assemble ./out/ for SD card
    make flash SD=/dev/sdX

Full pipeline:

    make all

See `docs/build-guide.md` for details.

## Runtime on the ZCU102

Both bitstreams and both userspace binaries are on the SD card after
`make sdcard`.

Boot defaults are set in `/etc/fpga-application.conf`:

    FPGA_DEFAULT=tdc

To swap at runtime (no reboot):

    sudo fpgautil -b /lib/firmware/coincidence.bit.bin
    sudo yeet-data-ct 192.168.1.100

To collect data on the host PC:

    pip install -r sw/host/requirements.txt
    python sw/host/collect_data.py -n 18000 192.168.1.100

## The PL contract

Any new bitstream dropped into this Linux image must keep the AXI
footprint documented in `docs/pl-contract.md`:

| Address        | Peripheral         | Direction | Width |
|---------------:|:-------------------|:----------|:------|
| `0xA0000000`   | `axi_dma_0`        | S2MM      | 128b  |
| `0xA0010000`   | `axi_gpio_ctrl`    | OUT       | 2     |
| `0xA0020000`   | `axi_gpio_status`  | IN        | 32    |
| `0xA0030000`   | `axi_gpio_config`  | OUT       | 64    |
| `0xA0040000`   | `axi_gpio_status2` | IN        | 32    |
| `0xA0050000`   | `axi_gpio_flags`   | IN        | 32    |

Clocks: `pl_clk0` = 100 MHz for AXI, `clk_wiz_0` = 400 MHz and 200 MHz
for the applications.
