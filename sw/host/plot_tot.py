#!/usr/bin/env python3
"""
plot_tot.py -- ToT histogram of one run (its tot.csv from make_tot.py),
on a linear and on a log scale.

    python plot_tot.py data/source_39mV            # the run folder or its tot.csv

Change the settings below and run it again. The PNGs are saved next to
tot.csv as tot_ch<N>.png and tot_ch<N>_log.png.
"""

import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from tdc_analysis import dac_mv, read_tot, threshold_of

# ---- settings -----------------------------------------------------------
CHANNEL = 0          # TDC channel, 0..3
BIN_NS = 0.5         # bin width in ns
TOT_MIN_NS = 0       # histogram range in ns
TOT_MAX_NS = None    # None: up to the longest 0.1 % of the hits
AS_RATE = False      # True: hits per second in each bin, False: counts
SAVE = True          # save the PNGs next to tot.csv
SHOW = True          # open the plot windows
# -------------------------------------------------------------------------

if len(sys.argv) != 2:
    sys.exit("usage: python plot_tot.py <run folder or tot.csv>")

header, data = read_tot(sys.argv[1])
folder = Path(sys.argv[1]) if Path(sys.argv[1]).is_dir() else Path(sys.argv[1]).parent
tot = data[data[:, 0] == CHANNEL, 2]
seconds = header["seconds"]
if len(tot) == 0:
    sys.exit(f"no hits on channel {CHANNEL} in {folder}")
if seconds is None and AS_RATE:
    sys.exit("the run time is unknown, so no rates: set AS_RATE = False")

req = threshold_of(header.get("threshold_mv", ""), CHANNEL)
threshold = f"threshold {dac_mv(req):.1f} mV" if req is not None else "threshold unknown"

top = TOT_MAX_NS if TOT_MAX_NS is not None else np.percentile(tot, 99.9)
bins = np.arange(TOT_MIN_NS, top + BIN_NS, BIN_NS)
outside = np.count_nonzero((tot < bins[0]) | (tot >= bins[-1]))

print(f"{folder}  channel {CHANNEL}, {threshold}")
print(f"  hits:     {len(tot)}  ({outside} outside {bins[0]:g} to {bins[-1]:g} ns)")
if seconds:
    print(f"  run time: {seconds:.1f} s, rate {len(tot) / seconds:.2f} Hz")
print(f"  ToT:      mean {tot.mean():.3f} ns, median {np.median(tot):.3f} ns, "
      f"RMS {tot.std():.3f} ns")
print(f"  calibration: {header.get('calibration', 'unknown')}")

if AS_RATE:
    weights = np.full(len(tot), 1 / seconds)
    ylabel = f"Rate (Hz per {BIN_NS:g} ns bin)"
else:
    weights = None
    ylabel = f"Counts per {BIN_NS:g} ns"

for log in (False, True):
    plt.figure()
    label = f"{len(tot)} hits" + (f", {seconds:g} s" if seconds else "")
    plt.hist(tot, bins=bins, weights=weights, histtype="step", label=label)
    if log:
        plt.yscale("log")
    plt.xlabel("ToT (ns)")
    plt.ylabel(ylabel)
    plt.title(f"Channel {CHANNEL} ToT, {threshold}")
    plt.legend()
    plt.tight_layout()
    if SAVE:
        name = f"tot_ch{CHANNEL}_log.png" if log else f"tot_ch{CHANNEL}.png"
        plt.savefig(folder / name)
        print(f"  saved {folder / name}")

if SHOW:
    plt.show()
