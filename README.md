# SCAM

So Can Anyone Make-this-work.

A modular FPGA + PetaLinux platform for physics DAQ, built around two
application bitstreams that share one Linux image:

- **TDC** -- 2-channel time-to-digital converter with DMA readout
- **CT**  -- 4-channel multifold coincidence trigger with timestamped FIFO

The Linux image, rootfs, and device tree are identical for both. The
bitstream is swapped at runtime via `fpgautil`; userspace applications
access PL registers through `/dev/mem`.

## Layout

    hw/base         Base Vivado project (PS + interconnect + GPIOs + DMA)
    hw/tdc          TDC application (VHDL + TCL on top of base)
    hw/ct           Coincidence trigger application (VHDL + TCL on top of base)
    sw/common       Shared C headers and helpers
    sw/tdc          TDC userspace application
    sw/ct           CT userspace application
    sw/host         Python UDP collector (runs on the host PC)
    petalinux       PetaLinux project skeleton
    scripts         Build, package, flash helpers
    docs            Architecture and workflow

## Build

Requires Vivado 2023.2+ and PetaLinux 2023.2+. See `docs/build-guide.md`.

    make base-xsa        # generate base XSA
    make bitstreams      # generate tdc.bit.bin + coincidence.bit.bin
    make petalinux       # build Linux image
    make sdcard          # assemble SD card artifacts into ./out/

## Runtime on ZCU102

Bitstreams and both userspace binaries are on the SD card. To swap:

    sudo fpgautil -b /lib/firmware/coincidence.bit.bin
    sudo yeet-data-ct 192.168.1.100

Or edit `/etc/fpga-application.conf` and reboot to change the default.

