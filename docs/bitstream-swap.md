# Bitstream Swap

## On the target (ZCU102)

Two bitstreams are preinstalled:

    /lib/firmware/tdc.bit.bin
    /lib/firmware/ct.bit.bin

Default at boot is set in `/etc/fpga-application.conf`:

    FPGA_DEFAULT=tdc

## Runtime swap (no reboot)

Stop any running application, then load the other bitstream:

    sudo scam-load ct
    sudo yeet-data-ct 192.168.1.100

`scam-load <name>` loads `/lib/firmware/<name>.bit.bin` through the kernel's
FPGA manager; with no argument it lists what is installed. No reboot required.

Do not load these files with `fpgautil -b /lib/firmware/<name>.bit.bin`:
`fpgautil` deletes the file from `/lib/firmware` after loading it.

## Boot-time default

Edit `/etc/fpga-application.conf` and set `FPGA_DEFAULT=ct`.
Then either reboot, or:

    sudo systemctl restart fpga-load.service

## Adding a new bitstream

Place the `.bit.bin` in `/lib/firmware/` and run `scam-load <name>`. As long as the
PL contract in `pl-contract.md` is respected, no Linux side changes are
needed. See `adding-an-app.md`.

## Notes

- `.bit.bin` is the ZynqMP-specific binary format, not the raw `.bit`
  produced by Vivado. `make <app>-bitstream` generates it with `bootgen`.
- Loading a bitstream while an application is actively reading the
  AXI bus can cause a bus stall. Stop the application first.
