# Host Collector

Python UDP receiver that saves incoming data to CSV. Runs on the host PC.

## Install

    pip install -r requirements.txt

## Usage

    python collect_data.py -n 18000 192.168.1.100
    python collect_data.py -n 18000 -v 1000 192.168.1.100
    python collect_data.py -t 60 -o run1.csv 192.168.1.100

## Packet formats

Auto-detected by size:

- 1440 bytes -> TDC packet (90 hits x 16 bytes)
- 8 bytes    -> CT packet (1 event, 64-bit word)

The CSV column layout differs per mode.

### TDC CSV

    Channel_ID, Rising_Coarse, Rising_Fine, Falling_Coarse, Falling_Fine

### CT CSV

    Timestamp, Coinc_Out, ABCD, BCD, ACD, ABD, ABC, CD, BD, BC, AD, AC, AB, D, C, B, A

## Options

    -n N          stop after N events
    -t S          stop after S seconds
    -v MV         set DAC threshold via SSH before starting
    -o FILE       output CSV (default: capture.csv)
    --host HOST   FPGA address for SSH (default: the positional argument)
    --no-ssh      do not trigger the remote app, just listen
