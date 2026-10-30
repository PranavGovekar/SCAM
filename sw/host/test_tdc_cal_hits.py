#!/usr/bin/env python3
"""
test_tdc_cal_hits.py -- how many hits does the code-density calibration need?

Takes one large capture (10 million hits or more), calibrates the delay lines
with only N of its hits, for N = 1000, 2000, ... 9000, 10000, 20000, ... up to
all of them, and measures the ToT RMS each calibration gives. The RMS falls as
N grows and levels off where the calibration is no longer the limit; that
saturation point is the answer.

Usage:
    python test_tdc_cal_hits.py --csv data/<run>/hits.csv          # analyse a capture
    python test_tdc_cal_hits.py -v 250 -n 11000000 data-yeeter.local # collect + analyse

Same signal as test_tdc.py: a pulse at random phase to the TDC clock (e.g.
100 MHz square wave from a generator on its own clock).

Method, per channel:
    - The hits are shuffled. A fixed set of them (--test-hits, default
      1 million) is held out and only used to measure ToT; the rest is the
      calibration pool, so a calibration is never judged on its own hits. The
      RMS with calibration and measurement on the same hits (what test_tdc.py
      does) is plotted as well for comparison.
    - For each N, up to --repeats disjoint sets of N hits are taken from the
      pool. Each set calibrates both delay lines (test_tdc.py's code density),
      and the ToT RMS of the held-out hits is computed with it. The spread over
      the sets gives the error bars.
    - The model RMS^2 = a + b/N is fitted: a is the RMS with a perfect
      calibration, b/N the part added by counting noise in the calibration.
      Saturation is given as the N where the RMS is within 10, 5 and 1 % of
      sqrt(a).
    - The ToT RMS is a weak test of the calibration. Both delay lines are
      calibrated with the same pulses, so their tables come from the same set
      of phases, shifted by the ToT; counting noise then shifts every ToT by
      about the same amount. It moves the mean (scatter T sqrt(x(1-x)/N),
      x = ToT/T mod 1) instead of widening the peak. The scatter of the mean
      between calibrations is therefore reported too.
    - Calibration error of one delay line: two disjoint sets of N hits give two
      tables; the RMS of their difference / sqrt(2), weighted by how often each
      code occurs, is the error of a single table. Counting statistics predict
      T / sqrt(6 N). This is what a single edge (timing against another
      channel) sees. In a ToT the two edges come from the same pulse and part
      of the error cancels, so ToT needs fewer hits than single-edge timing.

Output in <run>/cal_hits/:
    results.csv   one row per (N, set): held-out RMS and sigma, same-hit RMS,
                  calibration error of the start and stop line
    summary.txt   per N: mean and spread; the fit and the saturation points
    plots/ch<N>_rms_vs_hits.png, ch<N>_cal_error_vs_hits.png, ch<N>_tot_by_hits.png
"""

import argparse
import sys
from pathlib import Path

import numpy as np

import collect_data
import test_tdc
from test_tdc import CLOCK_PERIOD_PS

DEFAULT_COLLECT = 11_000_000   # 10 million for calibration + 1 million held out
DEFAULT_TEST_HITS = 1_000_000
MAX_TEST_FRACTION = 0.2        # small captures: hold out at most this share
DEFAULT_REPEATS = 10
MIN_N = 1000
SATURATION_LEVELS = (0.10, 0.05, 0.01)
MEAN_LEVELS_PS = (1.0, 0.5)
LINE_LEVELS_PS = (2.0, 1.0)
HIST_N = (1000, 10_000, 100_000, 1_000_000)   # ToT histograms shown, plus the whole pool


def n_steps(pool):
    """1000, 2000, ... 9000, 10000, 20000, ... up to the pool size, then the pool."""
    steps, decade = [], MIN_N
    while decade <= pool:
        steps += [m * decade for m in range(1, 10) if m * decade <= pool]
        decade *= 10
    if not steps or steps[-1] != pool:
        steps.append(pool)
    return steps


def cal_table(codes, length):
    """Code-density table as in test_tdc.code_density, with a fixed length so
    that every code of the held-out hits has an entry."""
    counts = np.bincount(codes, minlength=length).astype(float)
    return CLOCK_PERIOD_PS * (np.cumsum(counts) - counts / 2) / counts.sum()


def tot(hits, t_start, t_stop):
    return ((hits[:, 3] - hits[:, 1]) * CLOCK_PERIOD_PS
            - t_stop[hits[:, 4]] + t_start[hits[:, 2]])


def table_error(a, b, codes):
    """Error of one table from two independent ones, weighted by code occupancy."""
    d = (a - b)[codes]
    return float(np.sqrt(np.mean(d * d) / 2))


def fit_model(n, rms):
    """Fit rms^2 = a + b/N (relative weights). Returns a, b."""
    y = rms ** 2
    b, a = np.polyfit(1.0 / n, y, 1, w=1.0 / y)
    return float(a), float(b)


def analyse_channel(hits, ch, args, rng, plt, plot_dir, title):
    length = int(max(hits[:, 2].max(), hits[:, 4].max())) + 1
    hits = hits[rng.permutation(len(hits))]
    n_test = min(args.test_hits, int(MAX_TEST_FRACTION * len(hits)))
    test, pool = hits[:n_test], hits[n_test:]
    steps = n_steps(len(pool))
    lsb = CLOCK_PERIOD_PS / length

    raw = test_tdc.peak_stats(tot(test, test_tdc.raw_table(hits[:, 2]),
                                  test_tdc.raw_table(hits[:, 4])), lsb)
    rows, tot_samples = [], {}
    for n in steps:
        sets = max(1, min(args.repeats, len(pool) // n))
        tables = []
        for k in range(sets):
            cal = pool[k * n:(k + 1) * n]
            t_start, t_stop = cal_table(cal[:, 2], length), cal_table(cal[:, 4], length)
            tables.append((t_start, t_stop))
            held = tot(test, t_start, t_stop)
            s = test_tdc.peak_stats(held, lsb / 3)
            same = float(np.std(tot(cal, t_start, t_stop)))
            rows.append({"n": n, "set": k, "mean": s["mean"], "rms": s["rms"], "sigma": s["sigma"],
                         "same_rms": same, "err_start": np.nan, "err_stop": np.nan})
            if k == 0 and (n in HIST_N or n == len(pool)):
                tot_samples[n] = held
        # Calibration error from pairs of independent tables.
        for k in range(0, len(tables) - 1, 2):
            (a0, a1), (b0, b1) = tables[k], tables[k + 1]
            r = rows[-sets + k]
            r["err_start"] = table_error(a0, b0, test[:, 2])
            r["err_stop"] = table_error(a1, b1, test[:, 4])

    res = {key: np.array([r[key] for r in rows], dtype=float) for key in rows[0]}
    n_all = res["n"]
    per_n = []
    for n in steps:
        sel = n_all == n
        errs = np.concatenate([res["err_start"][sel], res["err_stop"][sel]])
        errs = errs[np.isfinite(errs)]
        per_n.append({
            "n": n, "sets": int(sel.sum()),
            "rms": res["rms"][sel].mean(), "rms_sd": res["rms"][sel].std(),
            "mean_sd": res["mean"][sel].std() if sel.sum() > 1 else np.nan,
            "sigma": res["sigma"][sel].mean(),
            "same": res["same_rms"][sel].mean(), "same_sd": res["same_rms"][sel].std(),
            "err": float(np.sqrt(np.mean(errs ** 2))) if len(errs) else np.nan,
        })

    n_arr = np.array([p["n"] for p in per_n], dtype=float)
    rms_arr = np.array([p["rms"] for p in per_n])
    a, b = fit_model(n_arr, rms_arr)
    floor = np.sqrt(a) if a > 0 else np.nan
    tot_mean = float(np.mean(tot_samples[steps[-1]]))
    frac = (tot_mean / CLOCK_PERIOD_PS) % 1
    b_mean = CLOCK_PERIOD_PS ** 2 * frac * (1 - frac)

    out = [f"\nchannel {ch}: {len(hits):,} hits, {n_test:,} held out, pool {len(pool):,}, "
           f"codes 0..{length - 1}",
           f"  raw (no calibration): ToT RMS {raw['rms']:.2f} ps on the held-out hits"]
    for line, codes in (("start", hits[:, 2]), ("stop", hits[:, 4])):
        counts = np.bincount(codes)
        used = np.nonzero(counts)[0]
        span = counts[used[0]:used[-1] + 1]
        empty = int(np.count_nonzero(span == 0))
        out.append(f"  {line:5} line: codes {used[0]}..{used[-1]}, {empty} of them never hit")
        if empty > test_tdc.MAX_EMPTY_FRACTION * len(span):
            out.append(f"  WARNING: the hits do not cover every phase of the TDC clock, so the "
                       f"code-density calibration and everything below is wrong. A periodic "
                       f"input whose recorded pulses step by a simple fraction of 2.5 ns (e.g. "
                       f"97.3 MHz) does this; 100 MHz works.")
    out += ["",
           f"  {'N':>10} {'hits/code':>9} {'sets':>4} {'RMS (ps)':>16} {'sigma':>7} "
           f"{'same-hit RMS':>16} {'mean scatter':>12} {'line err':>8}   (ps)"]
    for p in per_n:
        out.append(f"  {p['n']:>10,} {p['n'] / length:>9.1f} {p['sets']:>4} "
                   f"{p['rms']:>8.2f} +- {p['rms_sd']:<5.2f} {p['sigma']:>7.2f} "
                   f"{p['same']:>8.2f} +- {p['same_sd']:<5.2f} {p['mean_sd']:>12.2f} "
                   f"{p['err']:>8.2f}")
    out += ["",
            "  1) ToT RMS (precision)",
            f"  fit RMS^2 = a + b/N: sqrt(a) = {floor:.2f} ps (RMS with a perfect calibration), "
            f"b = {b:.3g} ps^2"]
    sat = {}
    for f in SATURATION_LEVELS:
        if a > 0 and b > 0:
            sat[f] = b / (a * ((1 + f) ** 2 - 1))
            out.append(f"  RMS within {f * 100:>4.0f} % of {floor:.2f} ps from N = {sat[f]:,.0f} "
                       f"({sat[f] / length:,.0f} hits per code)")
    out += ["",
            "  2) ToT mean (accuracy). Calibration noise shifts every ToT by the same amount,",
            "  so it moves the mean, not the RMS. Expected scatter of the mean between",
            f"  calibrations: T sqrt(x(1-x)/N), x = ToT/T mod 1 = {frac:.3f}"]
    for ps in MEAN_LEVELS_PS:
        out.append(f"  ToT mean within {ps} ps (1 sigma) from N = {b_mean / ps ** 2:,.0f}")
    out += ["",
            "  3) One delay line (single-edge timing, e.g. channel against channel).",
            "  Expected calibration error T/sqrt(6N), RMS over the codes hit"]
    for ps in LINE_LEVELS_PS:
        out.append(f"  one line within {ps} ps RMS from N = {CLOCK_PERIOD_PS ** 2 / (6 * ps ** 2):,.0f}")
    if n_test < args.test_hits:
        out.append(f"  NOTE: capture too small for {args.test_hits:,} held-out hits; "
                   f"held out {n_test:,}")

    plot_rms(plt, plot_dir / f"ch{ch}_rms_vs_hits.png", title, per_n, raw["rms"], a, b, sat,
             length)
    plot_error(plt, plot_dir / f"ch{ch}_cal_error_vs_hits.png", title, per_n, length, b_mean)
    plot_hists(plt, plot_dir / f"ch{ch}_tot_by_hits.png", title, tot_samples, tot_mean, lsb)
    return out, [dict(r, channel=ch) for r in rows]


# ---------------------------------------------------------------- plots

def plain_ticks(ax):
    from matplotlib.ticker import FuncFormatter, NullFormatter
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:g}"))
    ax.yaxis.set_minor_formatter(NullFormatter())


def per_code_axis(ax, length):
    top = ax.secondary_xaxis("top", functions=(lambda n: n / length, lambda c: c * length))
    top.set_xlabel("hits per fine code")


def plot_rms(plt, path, title, per_n, raw_rms, a, b, sat, length):
    n = np.array([p["n"] for p in per_n], dtype=float)
    fig, ax = plt.subplots()
    if a > 0:
        x = np.geomspace(n[0], n[-1], 300)
        ax.plot(x, np.sqrt(a + b / x), color="C0", linewidth=1, linestyle="--",
                label=f"fit sqrt(a + b/N), floor {np.sqrt(a):.2f} ps")
        ax.axhline(np.sqrt(a), color="C0", linewidth=0.8, linestyle=":")
    ax.errorbar(n, [p["same"] for p in per_n], yerr=[p["same_sd"] for p in per_n],
                color="C1", marker="s", markersize=4, linewidth=1.2, capsize=2,
                label="calibrated and measured on the same hits")
    ax.errorbar(n, [p["rms"] for p in per_n], yerr=[p["rms_sd"] for p in per_n],
                color="C0", marker="o", markersize=4, linewidth=2, capsize=2,
                label="measured on held-out hits")
    for f, n_sat in sat.items():
        if n[0] <= n_sat <= n[-1]:
            ax.axvline(n_sat, color="0.3", linewidth=0.8, linestyle="-.")
            ax.text(n_sat, 0.98, f" {f * 100:.0f} %\n {n_sat:,.0f}", transform=ax.get_xaxis_transform(),
                    va="top", ha="left", fontsize=8, color="0.3")
    ax.text(0.98, 0.55, f"without calibration: {raw_rms:.1f} ps", transform=ax.transAxes,
            ha="right", fontsize=9, color="0.3")
    ax.set_xscale("log")
    ax.set_xlabel("hits used for the calibration (N)")
    ax.set_ylabel("ToT RMS on held-out hits (ps)")
    ax.set_title(f"{title}: ToT RMS vs calibration hits")
    per_code_axis(ax, length)
    ax.legend(loc="center right", bbox_to_anchor=(1, 0.72))
    test_tdc.save(plt, fig, path)


def plot_error(plt, path, title, per_n, length, b_mean):
    n = np.array([p["n"] for p in per_n], dtype=float)
    err = np.array([p["err"] for p in per_n])
    mean_sd = np.array([p["mean_sd"] for p in per_n])
    fig, ax = plt.subplots()
    sel = np.isfinite(err)
    ax.plot(n, CLOCK_PERIOD_PS / np.sqrt(6 * n), color="C0", linewidth=1, linestyle="--",
            label="one delay line, expected T / sqrt(6N)")
    ax.plot(n[sel], err[sel], color="C0", marker="o", markersize=4, linewidth=2,
            label="one delay line, measured (start and stop)")
    sel = np.isfinite(mean_sd)
    ax.plot(n, np.sqrt(b_mean / n), color="C1", linewidth=1, linestyle="--",
            label="ToT mean, expected T sqrt(x(1-x)/N)")
    ax.plot(n[sel], mean_sd[sel], color="C1", marker="s", markersize=4, linewidth=2,
            label="ToT mean, measured scatter between calibrations")
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("hits used for the calibration (N)")
    ax.set_ylabel("calibration error, RMS (ps)")
    plain_ticks(ax)
    ax.set_title(f"{title}: calibration error vs hits")
    per_code_axis(ax, length)
    ax.legend(loc="upper right")
    test_tdc.save(plt, fig, path)


def plot_hists(plt, path, title, samples, ref, lsb):
    keys = sorted(samples)
    lo = min(np.percentile(samples[k] - ref, 0.05) for k in keys)
    hi = max(np.percentile(samples[k] - ref, 99.95) for k in keys)
    pad = 0.05 * (hi - lo)
    bins = np.arange(lo - pad, hi + pad, max(lsb / 3, (hi - lo + 2 * pad) / 250))
    cmap = plt.get_cmap("Blues")
    fig, ax = plt.subplots()
    for i, k in enumerate(keys):
        colour = cmap(0.35 + 0.65 * i / max(1, len(keys) - 1))
        ax.hist(samples[k] - ref, bins=bins, histtype="step", density=True, color=colour,
                linewidth=1.5, label=f"N = {k:,}: mean {np.mean(samples[k]) - ref:+.1f} ps, "
                                      f"RMS {np.std(samples[k]):.1f} ps")
    ax.set_xlabel(f"ToT - {ref / 1000:.4f} ns  (ps)")
    ax.set_ylabel("fraction of hits per ps")
    ax.set_ylim(top=ax.get_ylim()[1] * 1.3)
    ax.set_title(f"{title}: held-out ToT, calibrated with N hits\n"
                 "too few hits move the whole peak; its width hardly changes")
    ax.legend(loc="upper left")
    test_tdc.save(plt, fig, path)


# ---------------------------------------------------------------- main

def analyse(csv_path, run_dir, args):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    test_tdc.style(plt)

    data = test_tdc.load_capture(csv_path)
    out_dir = run_dir / "cal_hits"
    plot_dir = out_dir / "plots"
    plot_dir.mkdir(parents=True, exist_ok=True)
    threshold = test_tdc.read_run_info(run_dir).get("threshold_mv", "?")
    channels = sorted(int(c) for c in np.unique(data[:, 0]))
    channels = [c for c in channels if args.channel is None or c == args.channel]
    out = [f"run: {run_dir.name}", f"capture: {csv_path}", f"threshold_mv: {threshold}",
           f"hits: {len(data):,}, channels {channels}",
           f"held-out hits: {args.test_hits:,}, sets per N: up to {args.repeats}, seed {args.seed}"]
    rows = []
    rng = np.random.default_rng(args.seed)
    for ch in channels:
        hits = data[data[:, 0] == ch]
        if len(hits) < 5 * MIN_N:
            out.append(f"\nchannel {ch}: {len(hits)} hits, too few to analyse")
            continue
        title = f"{run_dir.name}, ch{ch}"
        lines, ch_rows = analyse_channel(hits, ch, args, rng, plt, plot_dir, title)
        out += lines
        rows += ch_rows

    if rows:
        keys = ["channel", "n", "set", "mean", "rms", "sigma", "same_rms", "err_start", "err_stop"]
        with open(out_dir / "results.csv", "w") as f:
            f.write(",".join(keys) + "\n")
            for r in rows:
                f.write(",".join(f"{r[k]:.4f}" if isinstance(r[k], float) else str(r[k])
                                 for k in keys) + "\n")
    out.append(f"\nresults: {out_dir}")
    text = "\n".join(out)
    (out_dir / "summary.txt").write_text(text + "\n")
    print(text)


def main():
    ap = argparse.ArgumentParser(description="ToT RMS vs number of calibration hits")
    ap.add_argument("host", nargs="?", help="board address, e.g. data-yeeter.local")
    ap.add_argument("-v", "--threshold", type=int, metavar="MV",
                    help="input threshold in mV (required to collect)")
    ap.add_argument("-n", "--hits", type=int, default=DEFAULT_COLLECT,
                    help=f"hits the board sends (default {DEFAULT_COLLECT:,}); "
                         "ask for more if packets are lost")
    ap.add_argument("--csv", help="analyse this hits.csv instead of collecting")
    ap.add_argument("--channel", type=int, help="only this channel")
    ap.add_argument("--test-hits", type=int, default=DEFAULT_TEST_HITS,
                    help=f"hits held out to measure ToT (default {DEFAULT_TEST_HITS:,})")
    ap.add_argument("--repeats", type=int, default=DEFAULT_REPEATS,
                    help=f"independent sets of N hits per step, at most (default {DEFAULT_REPEATS})")
    ap.add_argument("--seed", type=int, default=1, help="shuffle seed (default 1)")
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
        run_dir = collect_data.new_run_dir("tdc_cal_hits")
        _, csv_path, rows = collect_data.capture(args.host, "tdc", args.threshold,
                                                 max_events=args.hits, out_dir=run_dir)
        if rows == 0:
            sys.exit("No hits arrived. Check the signal, the threshold and that the "
                     "TDC bitstream is loaded (sudo scam-load tdc).")

    analyse(csv_path, run_dir, args)


if __name__ == "__main__":
    main()
