# Notes for AI agents working on SCAM

Read this before changing anything. Human-facing docs are in `README.md` and
`docs/`; this file holds what is easy to get wrong.

## What the project is

One PetaLinux image for the ZCU102, plus any number of swappable PL
bitstreams ("applications"). The kernel and device tree know nothing about the
PL: userspace programs reach PL registers through `/dev/mem`, and bitstreams
are loaded at runtime with `fpgautil`. An application is therefore two files on
the board: `/lib/firmware/<name>.bit.bin` and `/usr/bin/yeet-data-<name>`.

Tool versions are fixed: Vivado 2024.1 and PetaLinux 2024.1.

## Layout

| Path | Role |
| :-- | :-- |
| `hw/base/` | Base block design (`build_base_xsa.tcl`) and the shared application build (`scam_app.tcl`). Core. |
| `apps/<name>/hw/` | `bd.tcl` (block-design edits only), `src/` RTL, `constraints/` XDC |
| `apps/<name>/sw/` | C program; `Makefile` is three lines including `sw/common/app.mk` |
| `apps/<name>/app.conf` | optional `BITSTREAM=` / `BINARY=` names |
| `apps/_template/` | copied by `make new-app`; names starting with `_` are not applications |
| `sw/common/` | C helpers compiled into every application, and `app.mk` |
| `sw/host/collect_data.py` | host-side UDP collector that writes CSV |
| `petalinux/` | PetaLinux project; hand-written recipes for TDC and CT under `project-spec/meta-user/` |
| `scripts/` | everything the Makefile calls; `scripts/lib/common.sh` holds shared paths |
| `build/`, `out/`, `.cache/` | generated, gitignored |

Applications are discovered by `scripts/apps.sh` from `apps/` and from the
`SCAM_APPS` directories. Never hardcode `tdc` or `ct` in the Makefile or
scripts; go through `apps.sh`.

## Commands

`make help` lists every target. Run `make status` before building (it shows
what is built, what is stale and the commands needed, in order) and
`make doctor` on a new machine or when a tool fails. The ones that matter:

- `make base-xsa`, `make <app>-bitstream`, `make bitstreams` -- Vivado, 10 to 15 minutes per bitstream
- `make app-<app> SCAM_SDK=<dir>` -- cross-compile one program with the SDK
- `make petalinux`, `make sdcard`, `make sdk`, `make release` -- image side
- `make deploy APP=<app> TARGET=<user@board>`

Per-machine settings live in the gitignored `config.mk` (see
`config.mk.example`). On the maintainer's workstation it sets
`PETALINUX_ENV := container`, because PetaLinux does not build natively there.

## Rules that are enforced or easy to break

1. **PL contract** (`docs/pl-contract.md`). Six AXI peripherals at fixed
   addresses, three clock frequencies, one DMA interrupt. `scam_app.tcl` checks
   this after every `bd.tcl` and fails the build. An application must not add
   AXI peripherals; it uses the existing GPIOs as its registers.
2. **DMA buffer.** `0x70000000`, 1 MiB, is reserved `no-map` in
   `petalinux/project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi`
   and named by `DMA_RAM_BASE`/`DMA_RAM_SIZE` in `sw/common/reg_io.h`. Keep the
   two in step. Any other DDR address belongs to Linux.
3. **Data formats are defined in the RTL and repeated in software.** If you
   change one, change all of them:
   - TDC hit, 128 bits: `apps/tdc/hw/src/tdc_channel.vhd` (`fifo_din`) and
     `parse_tdc` in `sw/host/collect_data.py`.
   - CT event, 64 bits: `apps/ct/hw/src/four_fold_coincidence.vhd`
     (`fifo_wr_data`) and `parse_ct` in `collect_data.py`.
   - CT register bits: `apps/ct/hw/src/ct_top.vhd` header,
     `apps/ct/sw/yeet-data-ct.c`, and the CT section of `docs/pl-contract.md`.
4. **The base XSA lives only at `hw/base/system.xsa`.** `petalinux-config`
   empties `project-spec/hw-description/` before importing, so an XSA stored
   there deletes itself.
5. **Images are in `petalinux/images/linux`** because `petalinuxbsp.conf` sets
   `PLNX_DEPLOY_DIR`. Do not remove that line.
6. **Staged files are generated.** `scripts/stage_assets.sh` copies C sources
   and `.bit.bin` files into the recipe `files/` directories on every PetaLinux
   build. Edit the originals in `apps/` and `sw/common/`, never the copies.
7. **Config templates.** `config.template` and `rootfs_config.template` are
   copied only when `config`/`rootfs_config` do not exist. After editing a
   template: `make clean-petalinux-config`, then configure again.
8. **Login.** User `petalinux`, password `petalinux`, with sudo; root has no
   password. `make deploy` and `collect_data.py` rely on this account.

## Things that will waste your time

- **Vivado must be started through `scripts/run_vivado.sh`.** On the
  maintainer's machine it needs extra library paths that a `vivado()` shell
  function in `~/.bashrc` provides.
- **The Vivado license comes from a remote server.** A "valid license was not
  found" or "obsolete xilinxd daemon" error during synthesis is a server-side
  problem, not a project bug. Stop and tell the user.
- **Container PetaLinux builds:** run them through `make` (or export
  `PETALINUX_ENV=container` when calling `scripts/run_petalinux.sh` directly).
  The eSDK under `.cache/.../components/` must be removed whole or not at all;
  use `make clean-container-state`. `docs/troubleshooting.md` lists the known
  failure messages.
- **`make clean-hw` and `make clean-build` delete `hw/base/build`,** the
  editable base Vivado project. It may hold GUI edits that are not in the TCL.
  Ask before running them.
- **Long builds.** A full image build takes hours from clean, minutes when
  incremental. Run them in the background and wait for completion; do not poll
  with a process-name match that can match your own shell.

## How the maintainer wants changes made

- Do not add Makefile targets, scripts, test benches or documents that were not
  asked for. Propose them first.
- Fix problems in the code; do not write "known issues" documents in their place.
- The TDC RTL has been tested on hardware by the maintainer. Explain and get
  agreement before changing it.
- Keep explanations plain; the maintainer is a hardware person, not a Yocto
  specialist.

## State of verification

Everything builds from a clean tree. As of the last agent session, **nothing in
this list had been run on a real board**; treat each as unproven until someone
reports otherwise:

- `fpgautil` accepting the `.bit.bin` files (`scripts/build_hw.sh` runs
  `bootgen` without `-process_bitstream bin`; try that first if loading fails)
- the `.wic` SD image booting (its boot partition holds `Image`, not `image.ub`)
- the first DMA transfer in `yeet-data-tdc` (it no longer waits for the idle bit)
- the I2C DAC path through the kernel mux (`sw/common/i2c_dac.c`)
- the CT pop/acknowledge readout and the dropped-event counter
- the TDC RTL changes: a stop with no start is discarded, and a record is
  written only when the start line fired for that measurement

## Accepted limitations

- UDP packets carry no sequence number, so `collect_data.py` cannot detect a
  dropped packet. The maintainer has accepted this for now. Fixing it means
  changing the packet format in both C programs and the collector together.
