# SCAM

### **S**o, **C**an **A**nyone **M**ake-this-work?

Modular FPGA + PetaLinux platform for physics DAQ on the **Xilinx ZCU102**
(Zynq UltraScale+ XCZU9EG). Application bitstreams share one Linux image. Two
applications are included:

- **TDC** — 4-channel time-to-digital converter, DMA readout to DDR
- **CT**  — 4-channel multifold coincidence trigger, timestamped FIFO

The Linux image, rootfs, and device tree are identical for every application.
Bitstreams are swapped at runtime with `scam-load`; userspace code talks to PL
registers through `/dev/mem`. No kernel drivers are bound to PL peripherals, so
no reboot is needed to switch applications.

You can add your own application (hardware and software) on top of the
prebuilt image without touching the rest of the repository: see
[docs/adding-an-app.md](docs/adding-an-app.md).

---

## Table of contents

- [Quick start with a release image](#quick-start-with-a-release-image)
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

## Quick start with a release image

Nothing has to be built for this.

1. Download `scam-zcu102.img.xz` from the release.
2. Write it to an SD card of 8 GB or more with Rufus or balenaEtcher (both
   read the `.img.xz` directly), or on Linux:
   `xz -dc scam-zcu102.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync`.
   Everything on the card is erased.
3. Set the ZCU102 boot mode switch SW6 to SD: position 1 ON, positions 2, 3
   and 4 OFF. Insert the card, connect Ethernet, power on.
4. The board loads the TDC bitstream by itself and asks the network for an
   address (DHCP). To see the address, open the USB serial console
   (115200 baud), log in as `petalinux` / `petalinux` and run `ip addr`.
   The board's host name is `data-yeeter`; most PCs can also reach it as
   `data-yeeter.local`, e.g. `ssh petalinux@data-yeeter.local`.
5. On the PC, collect data (see [Runtime](#runtime-on-the-zcu102)). `-v` is
   the input threshold in mV, about half the pulse height:

       python3 -m venv sw/host/.venv                        # once
       sw/host/.venv/bin/pip install -r sw/host/requirements.txt  # once
       source sw/host/.venv/bin/activate                    # in each new terminal
       python sw/host/collect_data.py -v 250 -n 18000 <board-ip>

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
    sw/host         Python collector, ToT analysis and TDC tests (run on the host PC)
    data/           Captures, one folder per run (not in git)
    petalinux       PetaLinux project skeleton
    scripts         Build, package and flash helpers
    docs            Architecture, contract, build guide, test plan
    build/          Generated: bitstreams and binaries (build/apps/<name>/)

---

## Prerequisites

Build host (Linux):

- Xilinx Vivado 2024.1 (includes `bootgen`) -- for bitstreams
- The SCAM SDK, built with `make sdk` -- for C applications
- Xilinx PetaLinux 2024.1 -- only to build the Linux image yourself; it can
  run in the provided Ubuntu 22.04 container (`PETALINUX_ENV=container`)
- GNU Make, `bash`, `git`
- Python 3.9+ on the host PC (collector and analysis: paramiko, numpy, matplotlib)

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

No PetaLinux build is involved: copy the two files to the board (step 4 of
`docs/adding-an-app.md`). Applications can also live outside this
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

    make petalinux            # configure if needed, build Linux and BOOT.BIN; files in ./out/
    make sdcard SD=/dev/sdX   # partition a card and copy the files from ./out/ onto it

or, as one image file that any SD card writer can use:

    make image                # ./out/scam-zcu102.wic, and .img.xz for publishing
    make flash SD=/dev/sdX    # write that image to a card
    make sdk                  # SDK installer (cross toolchain for applications)

Full pipeline (base + bitstreams + Linux + SD card image):

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

Set the input threshold of the FMC DIO card before taking data. It powers up
at 0 V, where the card sees no pulses, and keeps its value until power-off:

    sudo threshold 250          # mV, about half the pulse height

To swap to the coincidence trigger at runtime (no reboot):

    sudo scam-load ct
    sudo yeet-data-ct 192.168.1.100

To swap back to TDC:

    sudo scam-load tdc
    sudo yeet-data-tdc 192.168.1.100

User LEDs on the ZCU102 show the inputs (TDC: channels 0 to 2 on LEDs 5 to
7; CT: A to D on LEDs 3 to 6): an LED is on while its input is above the
threshold. With the TDC, LEDs 0 to 4 run a pattern while it is enabled.

`scam-load <name>` loads `/lib/firmware/<name>.bit.bin`. Do not use
`fpgautil -b` on a file in `/lib/firmware`: it deletes the file after loading it.

To collect data on the host PC:

    source sw/host/.venv/bin/activate      # set up as in the quick start
    python sw/host/collect_data.py -v 250 -n 18000 <board-ip>             # TDC
    python sw/host/collect_data.py --app ct -v 250 -n 1000 <board-ip>     # CT
    python sw/host/test_tdc.py -v 250 <board-ip>                          # TDC test
    python sw/host/test_tdc_cal_hits.py -v 250 -n 20000000 <board-ip>     # calibration hits

The scripts set the threshold and start the program on the board over SSH, so
the `sudo threshold` and `sudo yeet-data-*` commands above are only needed
when you run them by hand. Results go to `data/`; see `sw/host/README.md`.

### ToT with a pedestal

A pedestal is an ordinary run without the source, at the same threshold. Take
it, take the run with the source, then turn both into ToT and plot:

    python sw/host/collect_data.py -v 39 -t 600 -o data/pedestal_39mV <board-ip>
    python sw/host/collect_data.py -v 39 -t 600 -o data/source_39mV <board-ip>
    python sw/host/make_tot.py data/pedestal_39mV data/source_39mV      # hits.csv -> tot.csv
    python sw/host/plot_tot.py data/source_39mV                         # linear and log
    python sw/host/plot_tot_pedestal.py data/source_39mV data/pedestal_39mV

The subtraction divides each histogram by its own run time, so the two runs
may have different lengths. The plot settings (channel, bin width, range) are
variables at the top of each plot script. Details in `sw/host/README.md`.

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

**`scam-load` says loading failed.**
The FPGA manager only accepts `.bit.bin` files produced by `bootgen` from
a `.bit` — do not feed the raw Vivado `.bit` directly. Check that
`make bitstreams` completed without errors, and look at `dmesg`.

**`/dev/mem` mmap fails with `EPERM` or `Operation not permitted`.**
The programs must run as root (`sudo`).

**No UDP packets arrive at the host PC.**
Check `ip addr` on the ZCU102 — GEM3 must be `UP` and on the same subnet
as the host. Confirm the application is running and the FIFO is not
empty before blaming the network.

**Bitstream swap leaves the PL wedged.**
Stop any running `yeet-data-*` program, then load the bitstream again with `scam-load`.

**`make petalinux` fails on a fresh host.**
PetaLinux 2024.1 needs an AMD-supported host distribution. On anything else
use the container: `make petalinux PETALINUX_ENV=container`. See
`docs/build-guide.md`.

---

