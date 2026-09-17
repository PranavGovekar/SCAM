# Troubleshooting

## PetaLinux fails with "device tree" errors

The device tree is generated from the base XSA. If you swapped XSAs or
edited `system-user.dtsi`, regenerate:

    cd petalinux
    petalinux-config --get-hw-description ../hw/base/build/
    petalinux-build

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
`sw/ct/yeet-data-ct.c` for the exact sequence.
