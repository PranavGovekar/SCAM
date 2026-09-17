# Bitstream Swap

## On the target (ZCU102)

Two bitstreams are preinstalled:

    /lib/firmware/tdc.bit.bin
    /lib/firmware/coincidence.bit.bin

Default at boot is set in `/etc/fpga-application.conf`:

    FPGA_DEFAULT=tdc

## Runtime swap (no reboot)

Stop any running application, then load the other bitstream:

    sudo systemctl stop yeet-data.service 2>/dev/null || true
    sudo fpgautil -b /lib/firmware/coincidence.bit.bin
    sudo yeet-data-ct 192.168.1.100

Typical swap time is ~50 ms. No reboot required.

## Boot-time default

Edit `/etc/fpga-application.conf` and set `FPGA_DEFAULT=coincidence`.
Then either reboot, or:

    sudo systemctl restart fpga-load.service

## Adding a new bitstream

Place the `.bit.bin` in `/lib/firmware/` and point `fpgautil` at it.
As long as the PL contract in `pl-contract.md` is respected, no Linux
side changes are needed.

## Notes

- `.bit.bin` is the ZynqMP-specific binary format, not the raw `.bit`
  produced by Vivado. Generate it with `bootgen`.
- Loading a bitstream while an application is actively reading the
  AXI bus can cause a bus stall. Stop the application first.
