# Build Guide

## Prerequisites

- Vivado 2023.2 or newer, with ZCU102 board files installed
- PetaLinux 2023.2 or newer
- Linux host recommended (Ubuntu 20.04 or 22.04)
- For SD flashing: `parted`, `mkfs.vfat`, `mkfs.ext4`, `tar`

## Order of operations

    make base-xsa
    make bitstreams
    make petalinux-config      # once
    make petalinux
    make sdcard

Or simply:

    make all

## Why base-xsa first

PetaLinux is configured from the base XSA, not the application XSAs.
`make base-xsa` writes `system.xsa` directly into
`petalinux/project-spec/hw-description/`. `make petalinux-config` then
reads it.

## Config templates

`petalinux/project-spec/configs/config.template` and
`rootfs_config.template` are provided as starting points.
`make petalinux-config` copies them to `config` and `rootfs_config`
and then runs `petalinux-config --get-hw-description`. From that point
on, the actual `config` and `rootfs_config` files are the source of
truth.

If you want to tweak the kernel or rootfs later:

    cd petalinux
    petalinux-config              # menuconfig
    petalinux-config -c rootfs
    petalinux-build

## Adding a new C application

1. Copy `sw/tdc/` as a template.
2. Adjust the register map and readout logic.
3. Add a `.bb` recipe under
   `petalinux/project-spec/meta-user/recipes-apps/`.
4. `make petalinux` -- the new binary appears in `/usr/bin/`.

## Adding a new bitstream

1. Create a new Vivado project under `hw/<name>/`, layering on the base.
2. `make bitstreams` will only build TDC and CT unless you add a target.
3. Drop the resulting `.bit.bin` into
   `petalinux/project-spec/meta-user/recipes-bsp/fpga-bitstreams/files/`.
4. Edit `fpga-bitstreams.bb` to install the new file.
5. `make petalinux` -- the new bitstream is now in `/lib/firmware/`.
