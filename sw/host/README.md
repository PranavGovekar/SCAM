# Host Collector

Python UDP receiver that saves incoming data to CSV. Runs on the host PC.

## Install

    pip install -r requirements.txt

## Usage

    python collect_data.py -n 18000 192.168.1.100              # TDC
    python collect_data.py --app ct -n 1000 192.168.1.100      # coincidence trigger
    python collect_data.py -n 18000 -v 1000 192.168.1.100
    python collect_data.py -t 60 -o run1.csv 192.168.1.100

The address is the board's. The collector logs in over SSH, starts
`yeet-data-tdc` or `yeet-data-ct` there through `sudo`, and saves what the
board sends back. Load the matching bitstream on the board first.

## Packet formats

Auto-detected by size:

- 1440 bytes -> TDC packet (90 hits x 16 bytes)
- 8 bytes    -> CT packet (1 event, 64-bit word)

The CSV column layout differs per mode.

### TDC CSV

    Channel_ID, Rising_Coarse, Rising_Fine, Falling_Coarse, Falling_Fine

Coarse values count 400 MHz clock cycles (2.5 ns). Fine values are delay-line
bins, 0 to 784. The decoder follows the 128-bit word that
`apps/tdc/hw/src/tdc_channel.vhd` writes.

### CT CSV

    Timestamp, Coinc_Out, ABCD, BCD, ACD, ABD, ABC, CD, BD, BC, AD, AC, AB, D, C, B, A

## Options

    --app tdc|ct  program to start on the board (default: tdc)
    -n N          stop after N events
    -t S          stop after S seconds
    -v MV         have the board program set the DAC threshold first
    -o FILE       output CSV (default: capture.csv)
    --user USER   SSH user on the board (default: petalinux)
    --password P  SSH and sudo password (default: petalinux)
    --no-ssh      do not start the board program, just listen
