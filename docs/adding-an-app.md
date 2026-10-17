# Adding Your Own Application

A SCAM application is two files on the board:

- a bitstream, `/lib/firmware/<name>.bit.bin`, built on top of the base design
- a userspace program, `/usr/bin/yeet-data-<name>`, that talks to the PL
  registers through `/dev/mem`

The Linux image does not know about either of them. You can therefore take the
prebuilt image from a SCAM release, build your two files, copy them to a
running board, and they work. You do not need PetaLinux, and you do not edit
any file that belongs to SCAM.

## What you need

| For | Tool |
| :-- | :-- |
| The bitstream | Vivado 2024.1 with ZCU102 board files (includes `bootgen`) |
| The program | The SCAM SDK, built with `make sdk` (needs PetaLinux once) or copied from someone who has built it |
| The board | A ZCU102 booted from the release SD image |

Install the SDK once (`make sdk` writes it to `petalinux/images/linux/sdk.sh`):

    sh petalinux/images/linux/sdk.sh -d ~/scam-sdk

## 1. Create the application

    make new-app NAME=myapp

This copies `apps/_template/` to `apps/myapp/`. To keep your work outside the
SCAM checkout, give a destination and tell the build about it:

    make new-app NAME=myapp DEST=~/my-scam-apps
    echo 'SCAM_APPS := $(HOME)/my-scam-apps' >> config.mk

`SCAM_APPS` is a colon-separated list. Each entry is either one application
directory or a directory of applications. `make list-apps` shows what was
found.

    myapp/
      app.conf              optional names (see below)
      hw/bd.tcl             block-design edits
      hw/src/               your RTL (*.vhd, *.vhdl, *.v, *.sv)
      hw/constraints/       your pin and timing constraints (*.xdc)
      sw/*.c, *.h           your program
      sw/Makefile           three lines, includes sw/common/app.mk

An application may have only `hw/` or only `sw/`.

## 2. Hardware: `hw/bd.tcl`

The build clones the base Vivado project, adds everything in `hw/src/` and
`hw/constraints/`, opens the block design, and then sources your `bd.tcl`. In
it you instantiate your RTL and connect it to what the base design provides:

| Base signal | Meaning |
| :-- | :-- |
| `zynq_ultra_ps_e_0/pl_clk0` | 100 MHz AXI clock |
| `clk_wiz_0/clk_out1`, `clk_out2` | 400 MHz and 200 MHz |
| `proc_sys_reset_0/peripheral_reset` | active-high reset |
| `axi_gpio_ctrl/gpio_io_o[1:0]` | bit0 = enable, bit1 = reset |
| `axi_gpio_config/gpio_io_o`, `gpio2_io_o` | 2 x 32 bits, CPU to PL |
| `axi_gpio_status/gpio_io_i` | 32 bits, PL to CPU |
| `axi_gpio_status2/gpio_io_i` | 32 bits, PL to CPU |
| `axi_gpio_flags/gpio_io_i` | 32 bits, PL to CPU |
| `axi_dma_0/S_AXIS_S2MM` | 128-bit AXI4-Stream into DDR |

The DMA stream input is driven by `idle_axis_source` in the base design. To
stream data, delete that cell and connect your own master (see
`apps/tdc/hw/bd.tcl`). To use the GPIOs only, leave it alone (see
`apps/ct/hw/bd.tcl`). The DMA may only write to the reserved buffer at
`DMA_RAM_BASE` (`sw/common/reg_io.h`).

Build:

    make myapp-bitstream

The result is `build/apps/myapp/myapp.bit.bin`. The Vivado project and its log
are in the same directory.

### The contract is checked

The image is built once from the base XSA, so your design must keep the fixed
AXI map, clocks and DMA interrupt of `pl-contract.md`. The build verifies this
after your `bd.tcl` runs and stops with a message such as:

    ERROR: SCAM PL contract violated (see docs/pl-contract.md):
    ERROR:   - extra AXI peripheral /axi_gpio_extra/S_AXI/Reg at 0xA0060000 (applications may not add AXI slaves)

Use the bits of `axi_gpio_config` as your register space and document the
assignment in your application's README.

## 3. Software: `sw/`

Every `*.c` in `sw/` is compiled together with the helpers in `sw/common/`
(`reg_io`, `udp`, `args`, `i2c_dac`), so `#include "reg_io.h"` just works.

    make app-myapp SCAM_SDK=~/scam-sdk

The result is `build/apps/myapp/yeet-data-myapp`. Put `SCAM_SDK` in `config.mk`
to avoid repeating it. Alternatively source the SDK environment yourself and
run `make` inside `sw/`:

    source ~/scam-sdk/environment-setup-cortexa72-cortexa53-xilinx-linux
    make -C apps/myapp/sw

`make -C apps/myapp/sw CC=gcc` gives a native build, useful for checking that
the code compiles; it cannot access the PL.

## 4. Put it on the board

Copy both files to the board, then install them (`sudo` asks for the
password, `petalinux`):

    scp build/apps/myapp/myapp.bit.bin build/apps/myapp/yeet-data-myapp petalinux@192.168.1.10:/tmp/
    ssh -t petalinux@192.168.1.10 'sudo install -m 0644 /tmp/myapp.bit.bin /lib/firmware/ && sudo install -m 0755 /tmp/yeet-data-myapp /usr/bin/'

Then on the board:

    sudo scam-load myapp
    sudo yeet-data-myapp

Both files are on the SD card's root filesystem, so they survive a reboot. To
load your bitstream at boot, set `FPGA_DEFAULT=myapp` in
`/etc/fpga-application.conf` on the board.

## Names: `app.conf`

Optional, plain `KEY=value` lines without quotes:

    BITSTREAM=myapp_v2         # bitstream file is myapp_v2.bit.bin
    BINARY=threshold           # program name (apps/threshold sets this)

Defaults are `<name>` and `yeet-data-<name>`.

## Baking an application into the image

Only needed if you build your own Linux image and want the application present
on a freshly written SD card. This is the one case where you edit files under
`petalinux/`. The application must live in `apps/` or in a `SCAM_APPS`
directory, exactly as above.

1. **Program.** Copy the recipe directory
   `petalinux/project-spec/meta-user/recipes-apps/yeet-data-tdc/` to
   `recipes-apps/yeet-data-myapp/`, rename the `.bb` file to
   `yeet-data-myapp.bb`, and replace `yeet-data-tdc` with `yeet-data-myapp`
   inside the `.bb` and `files/Makefile`. If you have more than one source
   file, list each in `SRC_URI` and in the Makefile rule.
2. **Bitstream.** In `recipes-bsp/fpga-bitstreams/fpga-bitstreams.bb`, add
   `file://myapp.bit.bin` to `SRC_URI` and an `install` line for it.
3. **Image.** In `recipes-core/images/petalinux-image-minimal.bbappend`, add
   `yeet-data-myapp` to `IMAGE_INSTALL:append`.
4. Build: `make myapp-bitstream petalinux`.

You do not copy sources or bitstreams into the recipe directories yourself.
`scripts/stage_assets.sh` does that on every PetaLinux build: it stages an
application's sources when `recipes-apps/<binary>/` exists, and its bitstream
when `fpga-bitstreams.bb` lists it. `make petalinux-app-myapp` rebuilds only
your recipe.
