#!/usr/bin/env python3
"""
test_tdc.py -- time-over-threshold (ToT) test of the SCAM TDC.

Collects hits from the board (1 million by default), plots the ToT
distribution of each channel with raw fine values, calibrates the start and
stop delay line of each channel with a code-density test, and plots ToT again
with the calibration applied. Everything goes into one run folder under data/.

Usage:
    python test_tdc.py -v 250 data-yeeter.local                  # collect + analyse
    python test_tdc.py --csv data/<run>/hits.csv                 # re-analyse a run
    python test_tdc.py -v 250 --cal data/<run>/calibration.json data-yeeter.local

The recorded hits must cover every phase of the TDC clock evenly, otherwise
the code-density test cannot see every bin. A 100 MHz square wave from a
generator on its own clock works: 6 periods are 24 TDC cycles, so the phase
creeps slowly through the whole clock period. Other frequencies can fail: at
97.3 MHz the TDC's dead time traps the recorded pulses in three phase bands.
Empty codes inside the used range (warned below) show this.

How a hit maps to time (apps/tdc/hw/src):
    Each channel has a start line (rising edge) and a stop line (falling edge).
    The fine code is the number of taps the edge travelled before the next
    400 MHz clock edge, so a larger code means an earlier edge:

        t   = coarse * T - t_line(fine)          T = 2.5 ns
        ToT = (f_coarse - r_coarse) * T - t_stop(f_fine) + t_start(r_fine)

    Start and stop coarse values have the same pipeline delay, so it cancels.

Code density: with edges at random phase, the number of hits on a code is
proportional to that code's bin width. Over the codes of one line,
    width(k)  = T * n_k / N
    t_line(k) = T * (n_0 + ... + n_(k-1) + n_k / 2) / N     (bin centre)
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np

import collect_data
from tdc_analysis import (CLOCK_PERIOD_PS, apply_table, code_density,  # noqa: F401
                          peak_stats, raw_table, tot_ps)
DEFAULT_HITS = 1_000_000
MIN_HITS_PER_CODE = 50     # below this the code-density table is noisy
MAX_EMPTY_FRACTION = 0.10  # more empty codes than this: phases not random
MIN_CHANNEL_HITS = 1000    # channels with fewer hits are only reported

SHOW = False               # keep figures open for plt.show()


# ---------------------------------------------------------------- analysis

def load_capture(path):
    """Return the capture as an int array: channel, r_coarse, r_fine, f_coarse, f_fine."""
    try:
        data = np.loadtxt(path, delimiter=",", skiprows=1, dtype=np.int64, ndmin=2)
    except (OSError, ValueError) as e:
        sys.exit(f"ERROR: cannot read {path} as a TDC capture ({e})")
    if data.shape[0] == 0 or data.shape[1] != 5:
        sys.exit(f"ERROR: {path} holds no TDC hits")
    return data


# ---------------------------------------------------------------- plots

def save(plt, fig, path):
    fig.tight_layout()
    fig.savefig(path)
    if not SHOW:
        plt.close(fig)


def style(plt):
    plt.rcParams.update({
        "figure.figsize": (9, 5.5), "figure.dpi": 100, "savefig.dpi": 150,
        "axes.grid": True, "grid.alpha": 0.3, "axes.titlesize": 11,
        "axes.labelsize": 10, "legend.fontsize": 9,
    })


def stats_text(s):
    return (f"hits   {s['hits']:,}\nmean   {s['mean'] / 1000:.4f} ns\n"
            f"RMS    {s['rms']:.1f} ps\nsigma  {s['sigma']:.1f} ps (fit)\n"
            f"FWHM   {s['fwhm']:.1f} ps")


def tot_bins(samples, ref, bin_ps):
    both = np.concatenate([s - ref for s in samples])
    lo, hi = np.percentile(both, [0.1, 99.9])
    pad = 0.15 * (hi - lo) + 2 * bin_ps
    width = max(bin_ps, (hi - lo + 2 * pad) / 200)
    return np.arange(lo - pad, hi + pad + width, width)


def plot_tot(plt, path, title, curves, ref, bins):
    """curves: list of (label, tot_ps, stats, colour, filled)."""
    fig, ax = plt.subplots()
    for label, tot, s, colour, filled in curves:
        ax.hist(tot - ref, bins=bins, histtype="stepfilled" if filled else "step",
                color=colour, alpha=0.45 if filled else 1.0, linewidth=1.5, label=label)
        if filled and np.isfinite(s["sigma"]):
            x = np.linspace(bins[0], bins[-1], 400)
            scale = s["hits"] * (bins[1] - bins[0]) / (s["sigma"] * np.sqrt(2 * np.pi))
            ax.plot(x, scale * np.exp(-0.5 * ((x - (s["mu"] - ref)) / s["sigma"]) ** 2),
                    color=colour, linewidth=1, linestyle="--", label=f"{label} Gaussian fit")
    texts = "\n\n".join(f"{label}\n{stats_text(s)}" if len(curves) > 1 else stats_text(s)
                        for label, _, s, _, _ in curves)
    ax.text(0.98, 0.97, texts, transform=ax.transAxes, ha="right", va="top", family="monospace",
            fontsize=8, bbox={"boxstyle": "round", "facecolor": "white", "alpha": 0.85})
    ax.set_xlabel(f"ToT - {ref / 1000:.4f} ns  (ps)")
    ax.set_ylabel("hits per bin")
    ax.set_title(title)
    ax.legend(loc="upper left")
    save(plt, fig, path)


def plot_line(plt, folder, title, line, info):
    lo, hi = info["codes"]
    k = np.arange(lo, hi + 1)
    panels = [
        ("codes", "hits per code", info["counts"], None),
        ("bin_width", "bin width (ps)", info["widths"], info["lsb_ps"]),
        ("dnl", "DNL (LSB)", info["dnl"], 0.0),
        ("inl", "INL (LSB)", info["inl"], 0.0),
    ]
    for name, ylabel, y, ref in panels:
        fig, ax = plt.subplots()
        if name == "inl":
            ax.plot(k, y, linewidth=1)
        else:
            ax.step(k, y, where="mid", linewidth=0.8)
        if name == "bin_width":
            ax.axhline(ref, color="C1", linewidth=1, label=f"mean {ref:.2f} ps")
            ax.legend(loc="upper right")
        elif name == "dnl":
            ax.axhline(0, color="k", linewidth=0.8)
            for g in (-0.5, 0.5):
                ax.axhline(g, color="C1", linewidth=0.8, linestyle="--")
        elif name == "inl":
            ax.axhline(0, color="k", linewidth=0.8)
        ax.set_xlim(lo, hi)
        ax.set_xlabel("fine code")
        ax.set_ylabel(ylabel)
        ax.set_title(f"{title}, {line} line: {ylabel.split(' (')[0]}  "
                     f"({info['hits']:,} hits, codes {lo}..{hi})")
        save(plt, fig, folder / f"{name}_{line}.png")


# ---------------------------------------------------------------- main

def read_run_info(run_dir):
    info = {}
    path = run_dir / "run.txt"
    if path.exists():
        for line in path.read_text().splitlines():
            if ": " in line and not line.startswith(" "):
                key, value = line.split(": ", 1)
                info[key] = value
    return info


def analyse(csv_path, run_dir, cal_path=None, show=False):
    global SHOW
    SHOW = show
    import matplotlib
    if not show:
        matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    style(plt)

    data = load_capture(csv_path)
    run_name = run_dir.name
    threshold = read_run_info(run_dir).get("threshold_mv", "?")
    channels = sorted(int(c) for c in np.unique(data[:, 0]))
    out = [f"run: {run_name}", f"capture: {csv_path}", f"threshold_mv: {threshold}",
           f"hits: {len(data)}, channels {channels}"]

    if cal_path:
        with open(cal_path) as f:
            cal = json.load(f)
        tables = {name: np.array(line["t_ps"]) for name, line in cal["lines"].items()}
        out.append(f"calibration: {cal_path}")
    else:
        cal = {"clock_period_ps": CLOCK_PERIOD_PS, "source": str(csv_path), "lines": {}}
        tables = {}

    for ch in channels:
        hits = data[data[:, 0] == ch]
        out.append(f"\nchannel {ch}: {len(hits)} hits")
        if len(hits) < MIN_CHANNEL_HITS:
            out.append(f"  too few hits to analyse (fewer than {MIN_CHANNEL_HITS})")
            continue
        folder = run_dir / "plots" / f"ch{ch}"
        folder.mkdir(parents=True, exist_ok=True)
        title = f"{run_name}, ch{ch}, threshold {threshold} mV"

        lsb = []
        for line, codes in (("start", hits[:, 2]), ("stop", hits[:, 4])):
            name = f"ch{ch}_{line}"
            if cal_path:
                if name not in tables:
                    sys.exit(f"ERROR: {cal_path} has no calibration for {name}")
                lsb.append(CLOCK_PERIOD_PS / len(tables[name]))
                continue
            table, info = code_density(codes)
            tables[name] = table
            lsb.append(info["lsb_ps"])
            lo, hi = info["codes"]
            out.append(f"  {line:5} line: codes {lo}..{hi}, mean bin {info['lsb_ps']:.2f} ps, "
                       f"DNL {info['dnl'].min():+.2f}..{info['dnl'].max():+.2f} LSB, "
                       f"INL {info['inl'].min():+.1f}..{info['inl'].max():+.1f} LSB")
            per_code = info["hits"] / (hi - lo + 1)
            if per_code < MIN_HITS_PER_CODE:
                out.append(f"  WARNING: only {per_code:.0f} hits per code; collect more "
                           f"for a reliable calibration")
            if info["empty"] > MAX_EMPTY_FRACTION * (hi - lo + 1):
                out.append(f"  WARNING: {info['empty']} of {hi - lo + 1} codes are empty; "
                           f"the input may be locked to the TDC clock")
            cal["lines"][name] = {"hits": info["hits"], "codes": [lo, hi],
                                  "t_ps": [round(float(t), 3) for t in table]}
            plot_line(plt, folder, title, line, info)

        bin_ps = float(np.mean(lsb))
        tot_raw = tot_ps(hits, raw_table(hits[:, 2]), raw_table(hits[:, 4]))
        tot_cal = tot_ps(hits, tables[f"ch{ch}_start"], tables[f"ch{ch}_stop"])
        # Raw times sit on the equal-bin grid, so raw histograms use one LSB per bin;
        # calibrated times do not, and get finer bins.
        s_raw, s_cal = peak_stats(tot_raw, bin_ps), peak_stats(tot_cal, bin_ps / 3)
        for label, s in (("raw", s_raw), ("calibrated", s_cal)):
            out.append(f"  ToT {label:10}: mean {s['mean'] / 1000:.4f} ns, RMS {s['rms']:.1f} ps, "
                       f"sigma {s['sigma']:.1f} ps, FWHM {s['fwhm']:.1f} ps")

        ref = s_cal["mean"]
        plot_tot(plt, folder / "tot_raw.png", f"{title}: ToT, raw fine values",
                 [("raw", tot_raw, s_raw, "C0", True)], ref, tot_bins([tot_raw], ref, bin_ps))
        plot_tot(plt, folder / "tot_calibrated.png", f"{title}: ToT, calibrated",
                 [("calibrated", tot_cal, s_cal, "C1", True)], ref,
                 tot_bins([tot_cal], ref, bin_ps / 3))
        plot_tot(plt, folder / "tot_compare.png", f"{title}: ToT, raw and calibrated",
                 [("raw", tot_raw, s_raw, "C0", False), ("calibrated", tot_cal, s_cal, "C1", True)],
                 ref, tot_bins([tot_raw, tot_cal], ref, bin_ps))

    if not cal_path:
        with open(run_dir / "calibration.json", "w") as f:
            json.dump(cal, f)
        out.append(f"\ncalibration saved: {run_dir / 'calibration.json'}")
    out.append(f"plots: {run_dir / 'plots'}")

    text = "\n".join(out)
    (run_dir / "summary.txt").write_text(text + "\n")
    print(text)
    if show:
        print("(close the plot windows to finish)")
        plt.show()


def main():
    ap = argparse.ArgumentParser(description="TDC ToT test with code-density calibration")
    ap.add_argument("host", nargs="?", help="board address, e.g. data-yeeter.local")
    ap.add_argument("-v", "--threshold", type=int, metavar="MV",
                    help="input threshold in mV (required to collect)")
    ap.add_argument("-n", "--hits", type=int, default=DEFAULT_HITS,
                    help=f"hits to collect (default {DEFAULT_HITS:,})")
    ap.add_argument("--csv", help="analyse this hits.csv instead of collecting")
    ap.add_argument("--cal", help="use this calibration.json instead of calibrating")
    ap.add_argument("--show", action="store_true", help="also open the plots in windows")
    args = ap.parse_args()

    if args.csv:
        csv_path = Path(args.csv)
        run_dir = csv_path.parent
    else:
        if not args.host:
            ap.error("give the board address, or --csv to analyse an existing run")
        if args.threshold is None:
            ap.error("set an input threshold with -v <mV>; "
                     "the card powers up at 0 V and then sees nothing")
        run_dir = collect_data.new_run_dir("tdc_test")
        _, csv_path, rows = collect_data.capture(args.host, "tdc", args.threshold,
                                                 max_events=args.hits, out_dir=run_dir)
        if rows == 0:
            sys.exit("No hits arrived. Check the signal, the threshold and that the "
                     "TDC bitstream is loaded (sudo scam-load tdc).")

    analyse(csv_path, run_dir, args.cal, args.show)


if __name__ == "__main__":
    main()
