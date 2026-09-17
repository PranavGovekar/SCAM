# Test Plan

Run in order. Each step must pass before the next is attempted.

## 1. Base XSA loads

- Program the base bitstream via JTAG or SD boot.
- On target: `ls /sys/class/fpga_manager/`.
- `sudo fpgautil -b /lib/firmware/base.bit.bin` succeeds.
- `devmem 0xA0010000 32` returns 0 (GPIO tri state).

## 2. TDC bitstream loads and enumerates

- `sudo fpgautil -b /lib/firmware/tdc.bit.bin`.
- `devmem 0xA0010000 32` and `devmem 0xA0020000 32` return values.
- Overflow counter at `0xA0020000` increments when enable is high and
  no hits are present (this should be 0 actually -- overflow only
  increments on FIFO full).

## 3. TDC captures hits

- Inject a known pattern into the differential SMA inputs from a pulse
  generator (e.g. 10 ns width, 1 kHz repetition, two channels with a
  fixed delay between them).
- Run `sudo yeet-data-tdc -n 900 192.168.1.100`.
- Host: `python collect_data.py -n 900 192.168.1.100 -o tdc.csv`.
- Verify: hit count matches expected, timestamp deltas match the pulse
  generator delay.

## 4. CT bitstream loads and enumerates

- `sudo fpgautil -b /lib/firmware/coincidence.bit.bin`.
- `devmem 0xA0040000 32` returns 0.
- `devmem 0xA0050000 32` returns `0x2` (FIFO empty).

## 5. CT captures coincidences

- Inject 4 pulse trains from a pattern generator, all within a 20 ns
  window.
- Run `sudo yeet-data-ct -n 900 192.168.1.100`.
- Host: `python collect_data.py -n 900 192.168.1.100 -o ct.csv`.
- Verify: coinc_out bit 14 (ABCD) is high on every event.

## 6. Boundary behavior

- Increase the inter-channel delay to > window_width.
- Verify: no 4-fold events, but 3-fold events appear correctly.

## 7. Veto behavior

- Drive veto_in high via firmware (bit in gpio_config).
- Verify: coinc_out still shows combinations, hw_trigger_out stays low.

## 8. Runtime swap stress

- Loop 50 times: load TDC, load CT, load TDC.
- Verify: no kernel panics, `/dev/mem` reads return sensible values
  after every swap.

## 9. Cold boot

- Reboot with SD card in.
- Verify: systemd loads the default bitstream, the default application
  is either auto-started or ready to run.
