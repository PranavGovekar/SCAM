# SCAM

### **S**o, **C**an **A**nyone **M**ake-this-work?

Modular FPGA + PetaLinux platform for physics DAQ on the **Xilinx ZCU102**
(Zynq UltraScale+ XCZU9EG). Application bitstreams share one Linux image. Two
applications are included:

- **TDC** — 2-channel time-to-digital converter, DMA readout to DDR
- **CT**  — 4-channel multifold coincidence trigger, timestamped FIFO

The Linux image, rootfs, and device tree are identical for every application.
Bitstreams are swapped at runtime with `fpgautil`; userspace code talks to PL
registers through `/dev/mem`. No kernel drivers are bound to PL peripherals, so
no reboot is needed to switch applications.

You can add your own application (hardware and software) on top of the
prebuilt image without touching the rest of the repository: see
[docs/adding-an-app.md](docs/adding-an-app.md).

---

## Table of contents

- [Hardware](#hardware)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Adding your own application](#adding-your-own-application)
- [Build](#build)
- [Runtime on the ZCU102](#runtime-on-the-zcu102)
- [The PL contract](#the-pl-contract)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---
## Hardware

- Board: ZCU102 rev 1.0
- Part: `xczu9eg-ffvb1156-2-e`
- Vivado: 2024.1
- PetaLinux: 2024.1
- Ethernet: PS GEM3 (MIO 64..77), 1 GbE
- Host PC connects over the same network, receives UDP on port 8080

---

## Repository layout

    hw/base         Base Vivado project (PS + interconnect + GPIOs + DMA)
                    and the shared application build script
    apps/tdc        TDC application: hw/ (VHDL + block-design TCL), sw/ (C)
    apps/ct         Coincidence trigger application: hw/, sw/
    apps/_template  Starting point for `make new-app`
    sw/common       Shared C helpers (reg_io, udp, i2c_dac, args) and app.mk
    sw/host         Python UDP collector (runs on the host PC)
    petalinux       PetaLinux project skeleton
    scripts         Build, package, flash, deploy helpers
    docs            Architecture, contract, build guide, test plan
    build/          Generated: bitstreams and binaries (build/apps/<name>/)

---

## Prerequisites

Build host (Linux):

- Xilinx Vivado 2024.1 (includes `bootgen`) -- for bitstreams
- The SCAM SDK from a release, or built with `make sdk` -- for C applications
- Xilinx PetaLinux 2024.1 -- only to build the Linux image yourself; it can
  run in the provided Ubuntu 22.04 container (`PETALINUX_ENV=container`)
- GNU Make, `bash`, `git`
- Python 3.9+ on the host PC (for the UDP collector)

Machine-specific settings (tool paths, `PETALINUX_ENV`) go in `config.mk`;
see `config.mk.example`.

Runtime target:

- ZCU102 rev 1.0 booting from SD card
- Host PC on the same 1 GbE subnet, UDP port 8080 open

---

## Adding your own application

    make new-app NAME=myapp                       # creates apps/myapp/ from the template
    make myapp-bitstream                          # Vivado -> build/apps/myapp/myapp.bit.bin
    make app-myapp SCAM_SDK=~/scam-sdk            # SDK    -> build/apps/myapp/yeet-data-myapp
    make deploy APP=myapp TARGET=petalinux@<ip>   # copy both to a running board

No PetaLinux build is involved. Applications can also live outside this
repository (`SCAM_APPS`). Full walkthrough: `docs/adding-an-app.md`.

---

## Build

`make help` lists every target. `make doctor` checks that the machine has the
tools the build needs, and `make status` shows what is built, what is out of
date, and what to run next. Bitstreams and binaries:

    make base-xsa            # generate the base XSA (hw/base/system.xsa)
    make bitstreams          # every application's .bit.bin
    make apps                # every application's binary (needs SCAM_SDK)

The Linux image (only if you are not using a release image):

    make petalinux           # configure if needed, then build the image
    make sdcard              # BOOT.BIN + SD image, assemble ./out/
    make flash SD=/dev/sdX   # write ./out/ to the SD card
    make sdk release         # SDK installer, then release files in out/release/

Full pipeline (base + bitstreams + image + SD card files):

    make all

Targets rebuild only what changed. See `docs/build-guide.md` for details.

---

## Runtime on the ZCU102

The TDC and CT bitstreams and userspace binaries are part of the image.

Log in on the serial console or over SSH as `petalinux`, password `petalinux`
(it has `sudo`). Change the password with `passwd` on a board that is on a
shared network.

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
    python sw/host/collect_data.py -n 18000 <board-ip>            # TDC
    python sw/host/collect_data.py --app ct -n 1000 <board-ip>    # CT

The collector starts the program on the board over SSH, so the `sudo
yeet-data-*` commands above are only needed when you run it by hand.

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
PetaLinux 2024.1 needs an AMD-supported host distribution. On anything else
use the container: `make petalinux PETALINUX_ENV=container`. See
`docs/build-guide.md`.

---

