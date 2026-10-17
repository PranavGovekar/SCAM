# Test Plan

Run in order. Each step must pass before the next is attempted.

## 1. The image boots and loads the default bitstream

- Boot from the SD card and log in as `petalinux`.
- `systemctl status fpga-load` shows the service succeeded.
- `cat /sys/class/fpga_manager/fpga0/state` prints `operating`.
- `sudo cat /sys/kernel/debug/clk/pl0_ref/clk_enable_count` is not 0.
- `ls /lib/firmware/` still lists both `.bit.bin` files after the load.

## 2. TDC bitstream loads and enumerates

- `sudo scam-load tdc`.
- `sudo devmem2 0xA0010000 w` returns 0 and does not hang.
- `sudo devmem2 0xA0020000 w` returns 0 (the overflow counter only counts
  when a channel FIFO is full).

## 3. TDC captures hits

- Connect a pulse generator on its own clock to FMC DIO channel 0 (and 1).
  User LEDs 3 and 4 light while the inputs are above the threshold; set it
  first with `sudo threshold <mV>`, about half the pulse height (it powers up
  at 0 V).
- Use a 100 MHz square wave. Some other frequencies (97.3 MHz, for one) trap
  the recorded pulses in a few clock phases because of the TDC's dead time,
  and the calibration comes out wrong; `summary.txt` then warns about empty
  codes.
- Host: `python sw/host/test_tdc.py -v <mV> <board-ip>` collects 1 million
  hits and writes plots, calibration and `summary.txt` to `data/`.
- Verify per channel: the start and stop lines cover one clock period of
  codes with no large empty stretches, and the calibrated ToT peak matches the
  generator's pulse width and is narrower than the raw one.
- Reference (100 MHz square wave, 0 to 500 mV, threshold 250 mV, channel 0):
  codes 1..663 on both lines, mean bin 3.8 ps, ToT 4.727 ns, RMS 15 ps raw
  and 5.8 ps calibrated.

## 4. CT bitstream loads and enumerates

- `sudo scam-load ct`.
- `sudo devmem2 0xA0040000 w` returns 0.
- `sudo devmem2 0xA0050000 w` returns `0x2` (FIFO empty).

## 5. CT captures coincidences

- Inject 4 pulse trains from a pattern generator, all within a 20 ns
  window. User LEDs 3 to 6 show inputs A to D.
- Host: `python sw/host/collect_data.py --app ct -v <mV> -n 900 <board-ip>`
  (it logs in as `petalinux` and starts `yeet-data-ct` on the board).
- Verify: coinc_out bit 14 (ABCD) is high on every event.

## 6. Boundary behavior

- Increase the inter-channel delay to > window_width.
- Verify: no 4-fold events, but 3-fold events appear correctly.

## 7. Runtime swap stress

- Loop 50 times: load TDC, load CT, load TDC.
- Verify: no kernel panics, `/dev/mem` reads return sensible values
  after every swap.

## 8. Cold boot

- Reboot with SD card in.
- Verify: systemd loads the default bitstream again and both `.bit.bin`
  files are still in `/lib/firmware/`.
