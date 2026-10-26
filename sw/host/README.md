# Host scripts

Run on the PC. Each run is saved in its own folder under `data/` (see
`data/README.md`).

| Script | Does |
| :-- | :-- |
| `collect_data.py` | starts `yeet-data-tdc` or `yeet-data-ct` on the board, saves what it sends |
| `threshold_scan.py` | TDC: rate and ToT of detector pulses against threshold, per channel |
| `make_master_cal.py` | TDC: one long board calibration, kept in `calibrations/` as a master |
| `make_tot.py` | TDC: a run's `hits.csv` to `tot.csv` (time and ToT in ns, calibrated) |
| `plot_tot.py` | TDC: ToT histogram of one `tot.csv`, linear and log |
| `plot_tot_pedestal.py` | TDC: ToT of a source run minus a pedestal run |
| `test_tdc.py` | TDC test: collects 1 million hits, plots ToT, calibrates the delay lines, plots again |
| `test_tdc_cal_hits.py` | TDC test: how many hits the code-density calibration needs |
| `tdc_analysis.py` | library: ToT, code density, calibration files, master lookup (used by the scripts above) |

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

`-v 250` sets every channel. `-v 0:120,1:150` sets only the card channels
named (card channel k is TDC channel k) and leaves the others as they are.
The calibration input is card channel 4 with the 4-channel TDC bitstream and
card channel 2 with the 2-channel one. The card's DAC channels are wired out
of order (card channel 3 is DAC channel 7); `collect_data.py` takes card
channels, the board's `threshold -c` takes DAC channels.

A threshold needs about 6 ms to settle at the comparator (10 kohm, 100 nF on
the card); the board programs wait 20 ms after setting it, so no hit of a run
is taken at the previous threshold. Every run also starts with the TDC and
DMA reset, which discards anything left from an earlier run. Only words with
a TDC channel ID (0 to 3) go into `hits.csv`; calibration records never
leave the board, and any other word is counted in `run.txt`
(`unknown_words_dropped`). Packets from any other sender than the board are
ignored, and a run refuses to start while a board program is still running.

## collect_data.py

    python sw/host/collect_data.py -v 250 -n 18000 data-yeeter.local          # TDC
    python sw/host/collect_data.py --app ct -v 1000 -n 1000 data-yeeter.local # CT
    python sw/host/collect_data.py -v 250 -t 60 data-yeeter.local             # 60 seconds
    python sw/host/collect_data.py -v 0:120,1:150 -t 60 data-yeeter.local     # per channel

The collector logs in over SSH, sets the threshold and starts the program
through `sudo`. Load the matching bitstream on the board first
(`sudo scam-load tdc` or `sudo scam-load ct`). Packets are stored as they
arrive and decoded at the end, so a fast stream is not slowed down.

    --app tdc|ct  program to start on the board (default: tdc)
    -v MV         input threshold for every channel, or CH:MV,CH:MV per channel
                  (required, except with --no-ssh)
    -n N          stop after N hits or events
    -t S          stop after S seconds
    -o DIR        run folder (default: data/<date>_<time>_<app>)
    --user USER   SSH user on the board (default: petalinux)
    --password P  SSH and sudo password (default: petalinux)
    --no-ssh      do not start the board program, just listen
    --cal-window S  TDC: calibrate for S seconds first (calibration input,
                    FMC DIO card channel 4)
    --cal-every S   TDC: calibrate again every S seconds

Output in the run folder: `hits.csv` and `run.txt` (settings, the PL die
temperature at the start and end, the board's summary, packets received and,
for the TDC, how many were lost). `run_seconds` in `run.txt` is how long the
board took data, measured from its start and end messages, without
calibration windows; rates are worked out from it.

TDC CSV:

    Channel_ID, Rising_Coarse, Rising_Fine, Falling_Coarse, Falling_Fine

Coarse values count 400 MHz clock cycles (2.5 ns). Fine values are delay-line
codes: how far the edge travelled before the next clock edge (larger =
earlier). The decoder (`parse_tdc`) follows the 128-bit word that
`apps/tdc/hw/src/tdc_channel.vhd` writes; packets are 1440 bytes (90 hits).

With `--cal-window`, the board calibrates its delay lines and sends the
tables in calibration packets (format in `apps/tdc/sw/README.md`). Each
calibration is saved as `calibrations/cal_<n>.json` in the format
`test_tdc.py --cal` reads, with the quality flags of each line and
`first_hit_row`: the number of `hits.csv` rows that came before it, so the
hits from that row on were taken after it. `run.txt` and the screen list each
calibration. A line whose packet was lost is listed as incomplete and not
saved.

    python sw/host/collect_data.py -v 250 -n 1000000 --cal-window 1 data-yeeter.local
    python sw/host/test_tdc.py --csv data/<run>/hits.csv --cal data/<run>/calibrations/cal_000.json

CT CSV (one 8-byte packet per event, decoded by `parse_ct`):

    Timestamp, Coinc_Out, ABCD, BCD, ACD, ABD, ABC, CD, BD, BC, AD, AC, AB, D, C, B, A

## threshold_scan.py

    python sw/host/threshold_scan.py --channels 0 --from 20 --to 400 --step 20 -t 10 data-yeeter.local
    python sw/host/threshold_scan.py --channels 0,1 --thresholds 30,50,80,120 -t 30 data-yeeter.local
    python sw/host/threshold_scan.py --analyse data/<scan folder>        # again, without the board

For detector pulses (random heights and times). At each threshold the scanned
channels are set to it (the other channels and the calibration input keep
theirs), one capture of `-t` seconds is taken (or `-n` hits), and every
scanned channel is analysed. It only reports; it does not set the thresholds
for later runs.

Reported per channel and threshold: hits, rate, FIFO overflows, packets lost,
and the ToT with each calibration (raw; the master nearest the die
temperature, or `--master FILE`): mean, median, RMS, fitted sigma, FWHM,
percentiles 5/25/75/95 % and the fraction of short pulses (`--short-ns`,
default 2 ns). `summary.txt` marks where the rate is flat against threshold
(neighbouring points within 20 %) and suggests the middle of that plateau:
a suggestion from the rate alone, check the plots. It also notes where the
ToT median jumps by more than a factor 2 from one threshold to the next: there
the threshold crosses a different part of the pulse (for example only an
overshoot), even if the rate does not change. Above about 1.5 M hits/s
for all channels together the readout drops hits (counted as overflows) and
the rate shown is capped.

Output in `data/<date>_<time>_threshold_scan/`: `thr_<mV>/` (one capture
each), `scan.json`, `scan.csv`, `summary.txt`, and per channel
`plots/ch<N>/`: rate against threshold, the ToT spectrum at each threshold
(one panel each, around its median), ToT statistics against threshold.

## ToT: pedestal, source, plots

A pedestal is an ordinary run without the source, at the same threshold.
Only the last step treats it differently.

    # 1. take data: pedestal (no source), then with the source
    python sw/host/collect_data.py -v 39 -t 600 -o data/pedestal_39mV data-yeeter.local
    python sw/host/collect_data.py -v 39 -t 600 -o data/source_39mV data-yeeter.local

    # 2. hits.csv -> tot.csv in each run folder
    python sw/host/make_tot.py data/pedestal_39mV data/source_39mV

    # 3. ToT histogram of one run, linear and log
    python sw/host/plot_tot.py data/source_39mV

    # 4. source minus pedestal
    python sw/host/plot_tot_pedestal.py data/source_39mV data/pedestal_39mV

Use `-t` (a fixed time) for these runs, not `-n`: the rates need the run time.

**make_tot.py** writes `tot.csv` into each run folder: a few `# key: value`
lines (run time, threshold, die temperature, calibration), then
`channel,time_ns,tot_ns`, one row per hit. The calibration is the master
nearest the run's die temperature; `--master FILE`, or `--master none` for raw
equal bins. Scan points work too: `make_tot.py data/<scan>/thr_*`.

**plot_tot.py** and **plot_tot_pedestal.py** have their settings as variables
at the top (channel, bin width, ToT range, counts or rate, save, show): edit
and run again. The PNGs go next to `tot.csv` (`tot_ch<N>.png`,
`tot_ch<N>_log.png`; `tot_ch<N>_pedestal(_log).png` and
`tot_ch<N>_net(_log).png` for the subtraction). The threshold in the titles is
the real DAC value (requested mV rounded down to a step of 12.94 mV).

The subtraction divides each histogram by its own run time, so the two runs
may have different lengths, and gives each bin the Poisson error
`sqrt(Ns/ts^2 + Np/tp^2)`. It also prints the net rate and the pedestal time
that would give the smallest error for that signal time
(`tp/ts = sqrt(pedestal rate / signal rate)`): a quiet pedestal needs less
time than the source run.

## make_master_cal.py

    python sw/host/make_master_cal.py -v 4:200 data-yeeter.local          # 270 s window
    python sw/host/make_master_cal.py -v 4:200 --window 60 data-yeeter.local
    python sw/host/make_master_cal.py -v 2:150 data-yeeter.local          # 2-channel bitstream

One long board calibration from the calibration input (card channel 4, a
free-running generator near 100 MHz), saved as
`calibrations/master_<date>_<time>_<temp>C.json` with the PL die temperature,
in the format `test_tdc.py --cal` reads. 270 s gives about 100 million hits
per delay line. Take it with the board warm (30 minutes or more after power-up):
the tables move by about 0.5 ps per degree. `threshold_scan.py` uses the master
nearest the die temperature of the scan. Masters are board-specific; the
`calibrations/` folder is not in git. `-v 4:<mV>` (`2:<mV>` with the
2-channel bitstream) sets only the calibration input's threshold. Lines
without hits (channels the loaded bitstream does not have) are left out of
the master and listed.

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
