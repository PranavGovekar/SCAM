# Host scripts

Run on the PC. Each run is saved in its own folder under `data/` (see
`data/README.md`).

| Script | Does |
| :-- | :-- |
| `collect_data.py` | starts `yeet-data-tdc` or `yeet-data-ct` on the board, saves what it sends |
| `test_tdc.py` | TDC test: collects 1 million hits, plots ToT, calibrates the delay lines, plots again |
| `test_tdc_cal_hits.py` | TDC test: how many hits the code-density calibration needs |

## Install

From the repository root, once:

    python3 -m venv sw/host/.venv
    sw/host/.venv/bin/pip install -r sw/host/requirements.txt

Then in each new terminal, before running a script:

    source sw/host/.venv/bin/activate

The PC firewall must let UDP port 8080 in from the board. With ufw:
`sudo ufw allow from <board-ip> to any port 8080 proto udp`. A cable is
better than Wi-Fi at full TDC rate: packets lost on the way cannot be
detected.

## Threshold

Every run needs `-v <mV>`, the input threshold of the FMC DIO card, about half
the pulse height. The card powers up at 0 V and then sees no pulses; the
setting stays until the board loses power.

## collect_data.py

    python sw/host/collect_data.py -v 250 -n 18000 data-yeeter.local          # TDC
    python sw/host/collect_data.py --app ct -v 1000 -n 1000 data-yeeter.local # CT
    python sw/host/collect_data.py -v 250 -t 60 data-yeeter.local             # 60 seconds

The collector logs in over SSH, sets the threshold and starts the program
through `sudo`. Load the matching bitstream on the board first
(`sudo scam-load tdc` or `sudo scam-load ct`). Packets are stored as they
arrive and decoded at the end, so a fast stream is not slowed down.

    --app tdc|ct  program to start on the board (default: tdc)
    -v MV         input threshold (required, except with --no-ssh)
    -n N          stop after N hits or events
    -t S          stop after S seconds
    -o DIR        run folder (default: data/<date>_<time>_<app>)
    --user USER   SSH user on the board (default: petalinux)
    --password P  SSH and sudo password (default: petalinux)
    --no-ssh      do not start the board program, just listen

Output in the run folder: `hits.csv` and `run.txt` (settings, the board's
summary, packets received and, for the TDC, how many were lost).

TDC CSV:

    Channel_ID, Rising_Coarse, Rising_Fine, Falling_Coarse, Falling_Fine

Coarse values count 400 MHz clock cycles (2.5 ns). Fine values are delay-line
codes: how far the edge travelled before the next clock edge (larger =
earlier). The decoder (`parse_tdc`) follows the 128-bit word that
`apps/tdc/hw/src/tdc_channel.vhd` writes; packets are 1440 bytes (90 hits).

CT CSV (one 8-byte packet per event, decoded by `parse_ct`):

    Timestamp, Coinc_Out, ABCD, BCD, ACD, ABD, ABC, CD, BD, BC, AD, AC, AB, D, C, B, A

## test_tdc.py

    python sw/host/test_tdc.py -v 250 data-yeeter.local                 # collect + analyse
    python sw/host/test_tdc.py --csv data/<run>/hits.csv                # analyse a run again
    python sw/host/test_tdc.py -v 250 --cal data/<run>/calibration.json data-yeeter.local

Time over threshold (ToT) is the falling minus the rising edge time of each
pulse. It is computed per channel twice: with raw fine values (equal bins),
then with each delay line calibrated by a code-density test. The recorded
hits must cover every phase of the TDC clock evenly. A 100 MHz square wave from
a generator on its own clock works: 6 periods are 24 TDC cycles, so the phase
creeps slowly through the whole clock period. Other frequencies can fail: at
97.3 MHz the TDC's dead time traps the recorded pulses in three phase bands
and the calibration comes out wrong (17 ps instead of 6 ps). The summary
warns when codes inside the used range are empty, which is how this shows.

Options: `-n` hits to collect (default 1000000), `--cal` use an earlier
calibration instead of calibrating, `--show` also open the plots.

Output in `data/<date>_<time>_tdc_test/`:

- `hits.csv`, `run.txt`
- `calibration.json`: time of each fine code, per delay line
- `summary.txt`: code range, mean bin width, DNL/INL, ToT mean, RMS, fitted
  sigma and FWHM, raw and calibrated
- `plots/ch<N>/`: `tot_raw.png`, `tot_calibrated.png`, `tot_compare.png`, and
  per delay line (`start`, `stop`) `codes_`, `bin_width_`, `dnl_`, `inl_`

Reference result (100 MHz square wave, 0 to 500 mV, threshold 250 mV,
channel 0): about 663 codes per clock period, mean bin 3.8 ps, ToT 4.727 ns,
RMS 15 ps raw and 5.8 ps calibrated.

## test_tdc_cal_hits.py

    python sw/host/test_tdc_cal_hits.py -v 250 -n 20000000 data-yeeter.local  # collect + analyse
    python sw/host/test_tdc_cal_hits.py --csv data/<run>/hits.csv             # analyse a run again

How many hits the code-density calibration needs. One large capture is cut up:
1 million hits are held out and only used to measure ToT; from the rest,
sets of N = 1000, 2000 ... 9000, 10000, 20000 ... hits (up to 10 separate
sets per N) each calibrate both delay lines, and the held-out ToT is computed
with every calibration. Same signal as `test_tdc.py`. A 20 million hit capture
takes under a minute on the board; the analysis needs about 1.5 GB of memory
per 10 million hits.

Options: `-n` hits the board sends (default 11000000; ask for more if packets
are lost), `--channel`, `--test-hits` (default 1000000), `--repeats`
(default 10), `--seed`.

Output in `<run>/cal_hits/`:

- `summary.txt`: per N the held-out ToT RMS (mean and spread over the sets),
  the RMS when calibrating and measuring on the same hits, the scatter of the
  ToT mean between calibrations and the error of one delay line's table; a fit
  RMS² = a + b/N and the N where the RMS is within 10, 5 and 1 % of its best;
  the N needed for the ToT mean and for one delay line to be right to 1 ps
- `results.csv`: one row per (N, set)
- `plots/ch<N>_rms_vs_hits.png`, `ch<N>_cal_error_vs_hits.png`,
  `ch<N>_tot_by_hits.png`

What it showed (100 MHz, 18.9 million hits, channel 0, 2026-10-16):

- ToT RMS is within 1 % of its best (6.02 ps) from about 15000 hits. That
  is a weak test of the calibration: start and stop are calibrated with the
  same pulses, so most of the counting error cancels in the ToT and only
  shifts the whole peak.
- The ToT mean and a single delay line (what timing one channel against
  another needs) are right to about 1 ps only from about 1 million hits,
  following counting statistics: one line's error is 2.5 ns / sqrt(6 N).
- 1 million hits, the `test_tdc.py` default, is therefore the minimum for a
  calibration used for absolute times.

The summary warns when the hits leave codes empty (see the 97.3 MHz note under
`test_tdc.py`); everything it reports is then wrong.
