# Troubleshooting

## PetaLinux fails with "device tree" errors

The device tree is generated from the base XSA. If you swapped XSAs or
edited `system-user.dtsi`, regenerate:

    make base-xsa
    make petalinux-config
    make petalinux

## Kernel hangs at boot

Almost always caused by a PL peripheral that the DT references but
that does not exist in the currently loaded bitstream. Remember:
**the DT must never reference PL peripherals**. Our `system-user.dtsi`
does not, so if a hang appears, look for a stale DT fragment under
`petalinux/build/`.

## `fpgautil` fails with "device or resource busy"

Something is holding the AXI bus. Check with:

    sudo lsof | grep mem

Stop the offending process and retry.

## `devmem` returns 0xFFFFFFFF

The address does not decode. This means the currently loaded bitstream
does not have a peripheral at that address. Confirm the bitstream is
loaded:

    cat /sys/class/fpga_manager/fpga0/state
    # should print "operating"

## TDC reads all zeros

- Confirm the differential inputs are actually toggling (scope the
  SMA pins).
- Confirm `en_i` bit is set at `0xA0010000`.
- Confirm reset is deasserted (bit 1 high at `0xA0010000`).

## CT FIFO reads stale data

The FIFO read is asynchronous to the AXI clock. After pulsing the pop
bit, wait at least 1 us before reading status. See
`apps/ct/sw/yeet-data-ct.c` for the exact sequence.

## Bitstream build stops with "PL contract violated"

Your `hw/bd.tcl` changed something the Linux image depends on: an AXI
address, a clock frequency, or the DMA interrupt, or it added an AXI
peripheral. The message lists each difference. See `pl-contract.md`.

## `make app-<name>` says "No cross compiler"

Install the SDK (`sh scam-zcu102-<version>-sdk.sh -d ~/scam-sdk`) and pass
`SCAM_SDK=~/scam-sdk`, or put it in `config.mk`.

## Vivado is not found, or fails to start

Set `VIVADO_SETTINGS` in `config.mk` to Vivado's `settings64.sh`. Without it
the build uses a `vivado` shell function from `~/.bashrc` if there is one,
otherwise `vivado` on `PATH`.

## PetaLinux in the container

- **`[ERROR]` with no text at `oe-init-build-env`.** The eSDK under
  `.cache/petalinux-2024.1-ubuntu22/components/` is incomplete. Run
  `make clean-container-state`, then `make petalinux-config`.
- **"No XSA/DTS found".** `petalinux-config` empties
  `project-spec/hw-description/` before copying the XSA in, so the XSA must
  never be stored there. It lives at `hw/base/system.xsa`.
- **`[Errno 21] Is a directory: .../components/yocto/.statistics/`.** The
  PetaLinux installation is mounted read-only and needs the writable
  `.statistics` overlay that `scripts/build_petalinux_container.sh` sets up.
  Do not mount the installation by hand.
- **"Error during writing of the configuration".** Kconfig cannot replace the
  bind-mounted config file. The wrapper sets `KCONFIG_OVERWRITECONFIG=1` for
  this.
- **A source download fails.** Run `make fetch-check`: it downloads every
  source without compiling and prints a `wget` line for each one that is
  missing. `CONFIG_PRE_MIRROR_URL` in `config.template` must stay set; the
  comment there explains why.

## Images are missing from `petalinux/images/linux`

`petalinuxbsp.conf` sets `PLNX_DEPLOY_DIR` to that directory. Without it
PetaLinux 2024.1 writes images to `petalinux/build/images/linux`, where
`petalinux-package` and `make sdcard` do not look.
