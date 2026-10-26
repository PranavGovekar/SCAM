#!/usr/bin/env python3
"""
plot_tot_pedestal.py -- ToT of a run with the source minus a pedestal run
(no source, same threshold), both from tot.csv files of make_tot.py.

    python plot_tot_pedestal.py data/source_39mV data/pedestal_39mV

Each histogram is divided by its own run time, so both are in hits per second
per bin and the runs may have different lengths. Then, bin by bin:

    net   = Ns/ts - Np/tp
    error = sqrt(Ns/ts^2 + Np/tp^2)          (Poisson, added in quadrature)

The PNGs go next to the signal's tot.csv: tot_ch<N>_pedestal(_log).png with
both runs, tot_ch<N>_net(_log).png with the difference. On the log scale only
the bins above zero of the difference can be drawn.

Change the settings below and run it again.
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
TOT_MAX_NS = None    # None: up to the longest 0.1 % of the signal hits
SAVE = True          # save the PNGs next to the signal's tot.csv
SHOW = True          # open the plot windows
# -------------------------------------------------------------------------

if len(sys.argv) != 3:
    sys.exit("usage: python plot_tot_pedestal.py <signal run or tot.csv> <pedestal run or tot.csv>")

sig_header, sig_data = read_tot(sys.argv[1])
ped_header, ped_data = read_tot(sys.argv[2])
folder = Path(sys.argv[1]) if Path(sys.argv[1]).is_dir() else Path(sys.argv[1]).parent
sig = sig_data[sig_data[:, 0] == CHANNEL, 2]
ped = ped_data[ped_data[:, 0] == CHANNEL, 2]
ts, tp = sig_header["seconds"], ped_header["seconds"]
if not ts or not tp:
    sys.exit("the run time of one of the runs is unknown, so its rate cannot be computed")
if len(sig) == 0:
    sys.exit(f"no signal hits on channel {CHANNEL}")

req = threshold_of(sig_header.get("threshold_mv", ""), CHANNEL)
req_ped = threshold_of(ped_header.get("threshold_mv", ""), CHANNEL)
threshold = f"threshold {dac_mv(req):.1f} mV" if req is not None else "threshold unknown"
if req is None or req_ped is None or dac_mv(req) != dac_mv(req_ped):
    print(f"WARNING: thresholds differ or are unknown: signal {req} mV, pedestal {req_ped} mV")

top = TOT_MAX_NS if TOT_MAX_NS is not None else np.percentile(sig, 99.9)
bins = np.arange(TOT_MIN_NS, top + BIN_NS, BIN_NS)
centres = (bins[:-1] + bins[1:]) / 2

n_sig, _ = np.histogram(sig, bins)
n_ped, _ = np.histogram(ped, bins)
net = n_sig / ts - n_ped / tp
err = np.sqrt(n_sig / ts**2 + n_ped / tp**2)

rate_s, rate_p = len(sig) / ts, len(ped) / tp
net_rate = rate_s - rate_p
net_err = np.sqrt(len(sig) / ts**2 + len(ped) / tp**2)
print(f"channel {CHANNEL}, {threshold}")
print(f"  signal:   {len(sig)} hits in {ts:.1f} s = {rate_s:.3f} Hz   ({folder})")
print(f"  pedestal: {len(ped)} hits in {tp:.1f} s = {rate_p:.3f} Hz")
print(f"  net:      {net_rate:.3f} +- {net_err:.3f} Hz")
if rate_p > 0:
    # Pedestal time that gives the smallest error on the net rate for the
    # same total time.
    print(f"  best pedestal time for this signal time: {ts * np.sqrt(rate_p / rate_s):.0f} s")

ylabel = f"Rate (Hz per {BIN_NS:g} ns bin)"


def save(name):
    plt.tight_layout()
    if SAVE:
        plt.savefig(folder / name)
        print(f"  saved {folder / name}")


for log in (False, True):
    plt.figure()
    plt.hist(sig, bins=bins, weights=np.full(len(sig), 1 / ts), histtype="step",
             label=f"signal, {len(sig)} hits, {ts:g} s")
    plt.hist(ped, bins=bins, weights=np.full(len(ped), 1 / tp), histtype="step",
             label=f"pedestal, {len(ped)} hits, {tp:g} s")
    if log:
        plt.yscale("log")
    plt.xlabel("ToT (ns)")
    plt.ylabel(ylabel)
    plt.title(f"Channel {CHANNEL} ToT, {threshold}")
    plt.legend()
    save(f"tot_ch{CHANNEL}_pedestal_log.png" if log else f"tot_ch{CHANNEL}_pedestal.png")

plt.figure()
plt.errorbar(centres, net, yerr=err, fmt=".")
plt.axhline(0, color="black", linewidth=0.8)
plt.xlabel("ToT (ns)")
plt.ylabel(ylabel)
plt.title(f"Channel {CHANNEL} ToT, signal - pedestal, {threshold}")
save(f"tot_ch{CHANNEL}_net.png")

plt.figure()
above = net > 0
plt.errorbar(centres[above], net[above], yerr=err[above], fmt=".")
plt.yscale("log")
# error bars reaching below zero just run off the bottom
if above.any():
    plt.ylim(bottom=0.5 * net[above].min())
plt.xlabel("ToT (ns)")
plt.ylabel(ylabel)
plt.title(f"Channel {CHANNEL} ToT, signal - pedestal, {threshold}\n(bins above zero only)")
save(f"tot_ch{CHANNEL}_net_log.png")

if SHOW:
    plt.show()
