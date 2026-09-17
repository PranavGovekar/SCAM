# SCAM

### **S**o, **C**an **A**nyone **M**ake-this-work?

Modular FPGA + PetaLinux platform for physics DAQ on the **Xilinx ZCU102**
(Zynq UltraScale+ XCZU9EG). Two application bitstreams share one Linux image:

- **TDC** — 2-channel time-to-digital converter, DMA readout to DDR
- **CT**  — 4-channel multifold coincidence trigger, timestamped FIFO

The Linux image, rootfs, and device tree are identical for both. Bitstreams
are swapped at runtime with `fpgautil`; userspace code talks to PL registers
through `/dev/mem`. No kernel drivers are bound to PL peripherals, so no
reboot is needed to switch applications.

---

## Table of contents

- [Status](#status)
- [Hardware](#hardware)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Build](#build)
- [Runtime on the ZCU102](#runtime-on-the-zcu102)
- [The PL contract](#the-pl-contract)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---
## Hardware

- Board: ZCU102 rev 1.0
- Part: `xczu9eg-ffvb1156-2-e`
- Vivado: 2023.2 or newer
- PetaLinux: 2023.2 or newer
- Ethernet: PS GEM3 (MIO 64..77), 1 GbE
- Host PC connects over the same network, receives UDP on port 8080

---

## Repository layout

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

---

## Prerequisites

Build host (Linux):

- Xilinx Vivado 2023.2+
- Xilinx PetaLinux 2023.2+
- GNU Make, `bash`, `git`, `bootgen`
- Python 3.9+ on the host PC (for the UDP collector)

Tested on Ubuntu 20.04 and 22.04.

Runtime target:

- ZCU102 rev 1.0 booting from SD card
- Host PC on the same 1 GbE subnet, UDP port 8080 open

---

## Build

One-time setup:

    make base-xsa            # generate base XSA, place in petalinux hw-description
    make petalinux-config    # only needed if you change the BSP or device tree

Per-application build:

    make bitstreams          # generate tdc.bit.bin + coincidence.bit.bin
    make petalinux           # build the Linux image
    make sdcard              # assemble ./out/ for SD card
    make flash SD=/dev/sdX   # write ./out/ to the SD card

Full pipeline (base + both bitstreams + image + SD card):

    make all

See `docs/build-guide.md` for details.

---

## Runtime on the ZCU102

Both bitstreams and both userspace binaries are on the SD card after
`make sdcard`.

Boot defaults are set in `/etc/fpga-application.conf`:

    FPGA_DEFAULT=tdc

To swap to the coincidence trigger at runtime (no reboot):

    sudo fpgautil -b /lib/firmware/coincidence.bit.bin
    sudo yeet-data-ct 192.168.1.100

To swap back to TDC:

    sudo fpgautil -b /lib/firmware/tdc.bit.bin
    sudo yeet-data-tdc 192.168.1.100

To collect data on the host PC:

    pip install -r sw/host/requirements.txt
    python sw/host/collect_data.py -n 18000 192.168.1.100

---

## The PL contract

Any new bitstream dropped into this Linux image **must** keep the AXI
footprint documented in `docs/pl-contract.md`. The addresses below are
baked into both userspace binaries and into the device tree — breaking
them is a hard error, not a warning.

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

---

## Troubleshooting

**`fpgautil` reports "Invalid bitstream".**
The FPGA manager only accepts `.bit.bin` files produced by `bootgen` from
a `.bit` — do not feed the raw Vivado `.bit` directly. Check that
`make bitstreams` completed without errors.

**`/dev/mem` mmap fails with `EPERM` or `Operation not permitted`.**
The PetaLinux default kernel enables strict devmem, which blocks mapping
the AXI region. Set `CONFIG_STRICT_DEVMEM=n` in the kernel config and
rebuild `petalinux`.

**No UDP packets arrive at the host PC.**
Check `ip addr` on the ZCU102 — GEM3 must be `UP` and on the same subnet
as the host. Confirm the application is running and the FIFO is not
empty before blaming the network.

**Bitstream swap leaves the PL wedged.**
Run `sudo fpgautil -R` to reset the FPGA manager, then re-load.

**`make petalinux` fails on a fresh host.**
PetaLinux 2023.2 needs `gcc-multilib`, `libssl-dev`, `chrpath`, and
`gawk`. See `docs/build-guide.md` for the full list.

---

