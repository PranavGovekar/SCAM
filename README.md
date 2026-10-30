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
- [Taking data](#taking-data)
- [The PL contract](#the-pl-contract)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Quick start with a release image

Nothing has to be built for this.

1. Download `scam-zcu102.img.xz` from the
   [Releases](../../releases) page (about 70 MB; it holds a 6 GB card image).
2. Write it to an SD card of 8 GB or more, as described in
   [Writing the SD card](#writing-the-sd-card). Everything on the card is
   erased.
3. Set the ZCU102 boot mode switch SW6 to SD: position 1 ON, positions 2, 3
   and 4 OFF. Insert the card, connect Ethernet, power on.
4. The board loads the TDC bitstream by itself and asks the network for an
   address (DHCP). To see the address, open the USB serial console
   (115200 baud), log in as `petalinux` / `petalinux` and run `ip addr`.
   The board's host name is `data-yeeter`; most PCs can also reach it as
   `data-yeeter.local`, e.g. `ssh petalinux@data-yeeter.local`.
5. On the PC, set up the Python tools, then take data as described in
   [Taking data](#taking-data):

       python3 -m venv sw/host/.venv                        # once
       sw/host/.venv/bin/pip install -r sw/host/requirements.txt  # once
       source sw/host/.venv/bin/activate                    # in each new terminal
       python sw/host/collect_data.py -v <mV> -t <seconds> <board-ip>

### Writing the SD card

`scam-zcu102.img.xz` is the whole card, compressed: the boot partition (FAT,
2 GB) and the Linux root file system (ext4, 4 GB) are both inside it. Do not
format or partition the card first, and do not unpack the file; the tools
below do that themselves and replace everything on the card.

**balenaEtcher** (Windows, macOS, Linux): *Flash from file*, choose
`scam-zcu102.img.xz`; *Select target*, choose the SD card; *Flash!*. It
checks the card after writing.

**Rufus** (Windows): *Device*, choose the SD card; *Boot selection*,
*SELECT* and choose `scam-zcu102.img.xz`; *START*.

**Linux command line:** find the card with `lsblk` (plug it in and look for
the new disk of the card's size, e.g. `/dev/sdb` or `/dev/mmcblk0`). Use the
whole disk, not a partition such as `/dev/sdb1`; a wrong name erases that
disk. Unmount it if the desktop mounted it, then write:

    sudo umount /dev/sdX?*
    xz -dc scam-zcu102.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

After writing, Windows sees only the small boot partition and may say the
other one must be formatted: cancel, it is the Linux partition and is fine.

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

The input threshold must be set before taking data; see
[Setting the threshold](#setting-the-threshold).

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

---

## Taking data

The scripts run on the PC, from the repository root, with the Python
environment of the [quick start](#quick-start-with-a-release-image) active
(`source sw/host/.venv/bin/activate`). They log in to the board over SSH,
set the threshold, start the board program and save what it sends. Each run
goes into its own folder under `data/`. The PC firewall must let UDP port
8080 in from the board (with ufw:
`sudo ufw allow from <board-ip> to any port 8080 proto udp`).

The numbers in the examples below only show the syntax.

### Inputs

| FMC DIO card channel | TDC | CT |
| :-- | :-- | :-- |
| 0, 1, 2, 3 | TDC channels 0, 1, 2, 3 | inputs A, B, C, D |
| 4 | calibration input | not used |

### Setting the threshold

Every card input has a comparator whose threshold comes from a DAC on the
card. The DAC starts at 0 V when the board is powered on and keeps its
setting until power-off, so set it for every session.

From the PC, with `-v` of `collect_data.py` (and of the other scripts):

| Argument | Sets |
| :-- | :-- |
| `-v MV` | every channel to MV millivolts |
| `-v CH:MV,CH:MV,...` | only the card channels named; the others keep their value |

On the board, by hand:

| Command | Sets |
| :-- | :-- |
| `sudo threshold MV` | every channel |
| `sudo threshold -c DAC MV` | one DAC channel |

The DAC channels are wired out of order on the card. `-v` takes card
channels; `threshold -c` takes DAC channels:

| Card channel | 0 | 1 | 2 | 3 | 4 |
| :-- | :-- | :-- | :-- | :-- | :-- |
| DAC channel | 0 | 1 | 2 | 7 | 4 |

The range is 0 to 3300 mV in 255 steps of 12.94 mV, rounded down: the real
threshold is `floor(MV * 255 / 3300) * 12.94` mV. The DAC cannot be read
back. The board programs wait 20 ms after setting it, so it has settled
before the first hit is taken.

### collect_data.py

    python sw/host/collect_data.py [options] <board-ip>

| Option | Meaning |
| :-- | :-- |
| `<board-ip>` | board address or host name, e.g. `data-yeeter.local` |
| `--app tdc\|ct` | program to start on the board (default `tdc`); load the matching bitstream first with `sudo scam-load tdc` or `ct` |
| `-v MV` or `-v CH:MV,...` | threshold, see above (required, except with `--no-ssh`) |
| `-t S` | stop after S seconds |
| `-n N` | stop after N hits (TDC) or events (CT) |
| `-o DIR` | run folder (default `data/<date>_<time>_<app>`) |
| `--cal-window S` | TDC: calibrate the delay lines for S seconds first, from the calibration input |
| `--cal-every S` | TDC: calibrate again every S seconds (needs `--cal-window`) |
| `--user U`, `--password P` | board login (default `petalinux` / `petalinux`) |
| `--no-ssh` | only listen; start the board program yourself |

Examples:

    python sw/host/collect_data.py -v 100 -t 600 -o data/my_run data-yeeter.local
    python sw/host/collect_data.py -v 0:100,1:150 -n 1000000 data-yeeter.local
    python sw/host/collect_data.py --app ct -v 100 -t 60 data-yeeter.local

The run folder holds:

| File | Contents |
| :-- | :-- |
| `hits.csv` | TDC: `Channel_ID, Rising_Coarse, Rising_Fine, Falling_Coarse, Falling_Fine`, one row per hit. CT: `Timestamp, Coinc_Out` and the 15 coincidence and single bits, one row per event |
| `run.txt` | settings, run time (`run_seconds`), PL die temperature at start and end, the board's summary, packets received and lost |
| `calibrations/cal_<n>.json` | TDC with `--cal-window`: one file per calibration |

Coarse values count 400 MHz clock cycles (2.5 ns). Fine values are delay-line
codes, larger = earlier.

### From hits to time over threshold (TDC)

    python sw/host/make_tot.py <run folder> [<run folder> ...] [--cal FILE|FOLDER|none]

Writes `tot.csv` into each run folder: `channel, time_ns, tot_ns`, one row
per hit, after a few `# key: value` header lines. `hits.csv` itself is always
the raw data.

The calibration is found by itself, the first of these that exists:

| Order | Calibration | Made by | Used for |
| :-- | :-- | :-- | :-- |
| 1 | `<run>/calibrations/self_calibration.json` | `make_self_cal.py` | every hit of the run |
| 2 | `<run>/calibrations/cal_<n>.json` | `collect_data.py --cal-window` | each from the hit it was taken before (`first_hit_row`); the first also for the hits before it |
| 3 | `calibrations/master_*.json` in the repository | `make_master_cal.py` | every hit; the master nearest the run's die temperature |
| 4 | none | | every fine code counts as an equal bin |

A run always gives one `tot.csv`, however many calibrations it has. The
calibration used is printed and written into the header of `tot.csv`.
`--cal FILE` (any calibration file) or `--cal FOLDER` (a `calibrations/`
folder) uses that instead; `--cal none` gives equal bins.

    python sw/host/make_self_cal.py <run folder> [<run folder> ...]

Makes `<run>/calibrations/self_calibration.json` from the run's own hits
(code density: the hits on each fine code are proportional to its width).
This needs hits that arrive at random times, such as detector pulses, and
enough of them (about 50 per code); the script warns when codes inside the
range are empty or have few hits. Delete the file to go back to the run's
board calibrations or a master.

    python sw/host/plot_tot.py <run folder>

`plot_tot.py` plots the ToT histogram of one run, linear and log; the PNGs go
next to `tot.csv`. It is set by variables at the top of the script:

| Variable | Meaning |
| :-- | :-- |
| `CHANNEL` | TDC channel, 0 to 3 |
| `BIN_NS` | bin width in ns |
| `TOT_MIN_NS`, `TOT_MAX_NS` | histogram range in ns (`TOT_MAX_NS = None`: up to the longest 0.1 % of the hits) |
| `AS_RATE` | hits per second instead of counts |
| `SAVE`, `SHOW` | save the PNGs, open the plot windows |

### Other scripts

| Script | Does |
| :-- | :-- |
| `threshold_scan.py` | TDC: one capture per threshold, rate and ToT against threshold per channel |
| `make_master_cal.py` | TDC: a long calibration from the calibration input, saved in `calibrations/` as a master |
| `test_tdc.py` | TDC test with a pulse generator: ToT before and after a code-density calibration |

Options and output of every script: [`sw/host/README.md`](sw/host/README.md).

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

