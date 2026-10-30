#!/usr/bin/env python3
"""
threshold_scan.py -- threshold scan of TDC channels with detector pulses.

For each threshold the scanned channels are set to it (the other channels and
the calibration input keep their thresholds), one capture is taken, and every
scanned channel is analysed. It only reports: it does not set thresholds for
later runs.

Reported per channel and threshold (everything; pick what you need):
    hits, rate (hits per second), board FIFO overflows, packets lost
    ToT with each calibration: mean, median, RMS, fitted sigma, FWHM,
    percentiles 5/25/75/95 %, fraction of short pulses (ToT < --short-ns)
Calibrations: raw (equal bins), calibrated (the master in calibrations/
nearest the die temperature, see make_master_cal.py, or --cal FILE; --cal none
for none), and with --self
a code-density calibration from the scan point's own hits (only right when
the pulses arrive at random times and there are enough of them).

summary.txt also marks, per channel, where the rate is flat (the plateau:
neighbouring points within 20 %) and suggests the middle of the longest
plateau. That is a suggestion from the rate alone; look at the plots.

    python threshold_scan.py --channels 0 --from 20 --to 400 --step 20 -t 10 data-yeeter.local
    python threshold_scan.py --channels 0,1 --thresholds 30,50,80,120 -t 30 data-yeeter.local
    python threshold_scan.py --channels 0 --also 2:150 -t 10 data-yeeter.local   # keep ch2 at 150 mV
    python threshold_scan.py --analyse data/<date>_threshold_scan          # again, no board
    python threshold_scan.py --channels 0 -t 2700 -n 10000000 --no-analysis ...   # long points: data only

--also CH:MV,... sets other channels once per point and leaves them there:
the calibration input, for example (after a power-up every threshold is 0 V).

Output in data/<date>_<time>_threshold_scan/: thr_<mV>/ (one capture each),
scan.json (settings), scan.csv, summary.txt, plots/ch<N>/.
"""

import argparse
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np

import collect_data
from tdc_analysis import (CLOCK_PERIOD_PS, apply_table, code_density, find_master, load_cal,
                          load_hits, peak_stats, raw_table, read_run_info, run_die_temp)

PLATEAU_STEP = 0.2         # neighbouring rates within 20 % count as flat
MIN_TOT_HITS = 20          # fewer hits: rate only, no ToT statistics
PERCENTILES = (5, 25, 75, 95)


# ---------------------------------------------------------------- analysis

def board_value(run_dir, label):
    """A number from the board's summary in run.txt, e.g. 'Overflow count'."""
    path = Path(run_dir) / "run.txt"
    if path.exists():
        for line in path.read_text().splitlines():
            if line.strip().startswith(label):
                try:
                    return int(line.split(":")[1])
                except (IndexError, ValueError):
                    return None
    return None


def packets_lost_pct(info):
    text = info.get("packets_received", "")
    if "% lost" in text:
        try:
            return float(text.split("(")[1].split("%")[0])
        except (IndexError, ValueError):
            return None
    return None


def tot_stats(tot, bin_ps, short_ps):
    s = peak_stats(tot, bin_ps)
    out = {"mean": s["mean"], "median": float(np.median(tot)), "rms": s["rms"],
           "sigma": s["sigma"], "fwhm": s["fwhm"],
           "short_pct": 100.0 * float(np.mean(tot < short_ps))}
    for p, v in zip(PERCENTILES, np.percentile(tot, PERCENTILES)):
        out[f"p{p}"] = float(v)
    return out


def analyse_point(run_dir, mv, channels, settings, cal_tables):
    data = load_hits(run_dir)
    info = read_run_info(run_dir)
    # The board ran for the whole -t unless -n was reached first; then the
    # span of the coarse times is the duration.
    duration = settings["seconds"]
    if settings.get("hits") and len(data) >= settings["hits"] and len(data) > 1:
        duration = (data[:, 1].max() - data[:, 1].min()) * CLOCK_PERIOD_PS * 1e-12
    rows, tots = [], {}
    for ch in channels:
        h = data[data[:, 0] == ch] if len(data) else data
        row = {"threshold_mv": mv, "channel": ch, "hits": len(h),
               "duration_s": round(duration, 4) if duration else None,
               "rate_hz": round(len(h) / duration, 3) if duration else None,
               "overflow": board_value(run_dir, "Overflow count"),
               "packets_lost_pct": packets_lost_pct(info),
               "die_temp_c": run_die_temp(info)}
        if len(h) >= MIN_TOT_HITS:
            tables = {"raw": (raw_table(h[:, 2]), raw_table(h[:, 4]))}
            if f"ch{ch}_start" in cal_tables and f"ch{ch}_stop" in cal_tables:
                tables["calibrated"] = (cal_tables[f"ch{ch}_start"], cal_tables[f"ch{ch}_stop"])
            if settings.get("self"):
                tables["self"] = (code_density(h[:, 2])[0], code_density(h[:, 4])[0])
            for v, (t_start, t_stop) in tables.items():
                tot = ((h[:, 3] - h[:, 1]) * CLOCK_PERIOD_PS
                       - apply_table(t_stop, h[:, 4]) + apply_table(t_start, h[:, 2]))
                bin_ps = CLOCK_PERIOD_PS / len(t_start) * (1 if v == "raw" else 1 / 3)
                for k, val in tot_stats(tot, bin_ps, settings["short_ns"] * 1000).items():
                    row[f"{v}_{k}_ps" if k != "short_pct" else f"{v}_short_pct"] = round(val, 3)
                if v == ("calibrated" if "calibrated" in tables else "raw"):
                    tots[ch] = tot
        rows.append(row)
    return rows, tots


def plateaus(points):
    """points: [(mV, rate)] sorted by mV. Returns the runs of neighbouring
    points whose rates differ by less than PLATEAU_STEP, longest first."""
    runs, cur = [], []
    for (mv0, r0), (mv1, r1) in zip(points, points[1:]):
        flat = r0 > 0 and r1 > 0 and abs(r1 / r0 - 1) < PLATEAU_STEP
        if flat:
            cur = cur or [mv0]
            cur.append(mv1)
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    return sorted(runs, key=len, reverse=True)


# ---------------------------------------------------------------- plots

def make_plots(out, rows, all_tots, variant):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"figure.figsize": (9, 5.5), "savefig.dpi": 130, "axes.grid": True,
                         "grid.alpha": 0.3})
    for ch in sorted({r["channel"] for r in rows}):
        folder = out / "plots" / f"ch{ch}"
        folder.mkdir(parents=True, exist_ok=True)
        rs = sorted((r for r in rows if r["channel"] == ch), key=lambda r: r["threshold_mv"])
        mv = [r["threshold_mv"] for r in rs]

        fig, ax = plt.subplots()
        ax.semilogy(mv, [max(r["rate_hz"] or 0, 1e-3) for r in rs], "o-")
        ax.set_xlabel("threshold (mV)")
        ax.set_ylabel("rate (hits/s)")
        ax.set_title(f"ch{ch}: rate against threshold")
        fig.tight_layout()
        fig.savefig(folder / "rate_vs_threshold.png")
        plt.close(fig)

        for key, label in (("median", "ToT median"), ("mean", "ToT mean"), ("rms", "ToT RMS"),
                           ("sigma", "ToT fitted sigma"), ("fwhm", "ToT FWHM")):
            fig, ax = plt.subplots()
            for v in ("raw", "calibrated", "self"):
                y = [r.get(f"{v}_{key}_ps", math.nan) for r in rs]
                if not all(isinstance(t, float) and math.isnan(t) for t in y):
                    ax.plot(mv, [t / 1000 for t in y], "o-", label=v)
            ax.set_xlabel("threshold (mV)")
            ax.set_ylabel(f"{label} (ns)")
            ax.set_title(f"ch{ch}: {label} against threshold")
            if ax.get_legend_handles_labels()[0]:
                ax.legend()
            fig.tight_layout()
            fig.savefig(folder / f"tot_{key}_vs_threshold.png")
            plt.close(fig)

        tots = [(m, all_tots[m][ch]) for m in mv if ch in all_tots.get(m, {}) and len(all_tots[m][ch])]
        if tots:
            # One panel per threshold, each on its own range: the ToT can
            # change by orders of magnitude between thresholds.
            cols = min(4, len(tots))
            nrows = math.ceil(len(tots) / cols)
            fig, axes = plt.subplots(nrows, cols, figsize=(3.2 * cols, 2.4 * nrows), squeeze=False)
            for ax, (m, t) in zip(axes.flat, tots):
                med = float(np.median(t))
                lo, hi = np.percentile(t - med, [0.5, 99.5])
                ax.hist(t - med, bins=np.linspace(lo, hi + 1e-9, 80), histtype="stepfilled", alpha=0.6)
                ax.set_title(f"{m} mV: median {med / 1000:.3f} ns, {len(t):,} hits", fontsize=8)
                ax.tick_params(labelsize=7)
            for ax in list(axes.flat)[len(tots):]:
                ax.axis("off")
            fig.suptitle(f"ch{ch}: ToT spectrum per threshold, ToT - median (ps), {variant}")
            fig.tight_layout()
            fig.savefig(folder / "tot_spectra.png")
            plt.close(fig)


# ---------------------------------------------------------------- main

def analyse_scan(out, cal_arg=None):
    settings = json.loads((out / "scan.json").read_text())
    channels = settings["channels"]
    points = sorted(int(p.name[4:]) for p in out.glob("thr_*") if (p / "hits.csv").exists())
    if not points:
        sys.exit(f"ERROR: no scan points in {out}")

    temps = [run_die_temp(read_run_info(out / f"thr_{mv:04d}")) for mv in points]
    temps = [t for t in temps if t is not None]
    temp = sum(temps) / len(temps) if temps else None
    cal_path, cal_note = None, "none (equal bins)"
    if cal_arg and cal_arg != "none":
        cal_path, cal_note = Path(cal_arg), cal_arg
    elif cal_arg != "none":
        found = find_master(temp)
        if found:
            cal_path = found[0]
            cal_note = f"master {found[0].name} (made at {found[1]} C" + (
                f", scan {found[2]:+.1f} C from it)" if found[2] is not None else ")")
    cal_tables = load_cal(cal_path) if cal_path else {}

    rows, all_tots = [], {}
    for mv in points:
        r, tots = analyse_point(out / f"thr_{mv:04d}", mv, channels, settings, cal_tables)
        rows += r
        all_tots[mv] = tots

    keys = []
    for r in rows:
        keys += [k for k in r if k not in keys]
    with open(out / "scan.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys, restval="")
        w.writeheader()
        w.writerows(rows)

    variant = "calibrated" if cal_tables else "raw"
    lines = [f"scan: {out}", f"channels: {channels}, thresholds {points[0]}..{points[-1]} mV "
             f"({len(points)} points), {settings['seconds']} s per point",
             f"die temperature: {'not read' if temp is None else f'{temp:.1f} C'}",
             f"calibration: {cal_note}",
             f"short pulses: ToT < {settings['short_ns']} ns", ""]
    for ch in channels:
        rs = sorted((r for r in rows if r["channel"] == ch), key=lambda r: r["threshold_mv"])
        lines.append(f"channel {ch} (ToT {variant}):")
        lines.append(f"  {'mV':>5} {'hits':>9} {'rate/s':>11} {'short%':>7} {'median ns':>10} "
                     f"{'mean ns':>9} {'RMS ps':>9} {'p5 ns':>8} {'p95 ns':>8} {'overflow':>9}")
        for r in rs:
            def g(k, scale=1.0, fmt="9.3f"):
                v = r.get(k)
                return format(v / scale, fmt) if isinstance(v, (int, float)) else format("-", ">" + fmt.split(".")[0])
            lines.append(f"  {r['threshold_mv']:5d} {r['hits']:9d} {g('rate_hz', 1, '11.1f')} "
                         f"{g(f'{variant}_short_pct', 1, '7.2f')} {g(f'{variant}_median_ps', 1000, '10.3f')} "
                         f"{g(f'{variant}_mean_ps', 1000, '9.3f')} {g(f'{variant}_rms_ps', 1, '9.1f')} "
                         f"{g(f'{variant}_p5_ps', 1000, '8.3f')} {g(f'{variant}_p95_ps', 1000, '8.3f')} "
                         f"{g('overflow', 1, '9.0f')}")
        flat = plateaus([(r["threshold_mv"], r["rate_hz"] or 0) for r in rs])
        if flat:
            best = flat[0]
            lines.append(f"  rate flat (within {PLATEAU_STEP:.0%} per step) from {best[0]} to {best[-1]} mV; "
                         f"suggested threshold {best[len(best) // 2]} mV (middle)")
            low = best[1] if len(best) > 2 else best[0]
            lines.append(f"  for ToT as a pulse-height measure: {low} mV, one step above the lowest flat "
                         f"point (longest ToT, most range, still clear of the noise)")
            for other in flat[1:3]:
                lines.append(f"  also flat: {other[0]} to {other[-1]} mV")
        else:
            lines.append("  no flat region in the rate: take more points or longer per point")
        medians = [(r["threshold_mv"], r.get(f"{variant}_median_ps")) for r in rs]
        medians = [(m, v) for m, v in medians if isinstance(v, (int, float)) and v > 0]
        for (m0, v0), (m1, v1) in zip(medians, medians[1:]):
            if v1 / v0 > 2 or v1 / v0 < 0.5:
                lines.append(f"  ToT median changes from {v0 / 1000:.3f} to {v1 / 1000:.3f} ns between "
                             f"{m0} and {m1} mV: the threshold crosses a different part of the pulse there")
        if any((r.get("overflow") or 0) > 0 for r in rs):
            lines.append("  WARNING: FIFO overflows at some points: the rate there is capped by the readout "
                         "(about 1.5 M hits/s for all channels together)")
        lines.append("")
    text = "\n".join(lines)
    (out / "summary.txt").write_text(text + "\n")
    print(text)
    make_plots(out, rows, all_tots, variant)
    print(f"plots: {out / 'plots'}")


def main():
    ap = argparse.ArgumentParser(description="TDC threshold scan for detector pulses")
    ap.add_argument("host", nargs="?", help="board address, e.g. data-yeeter.local")
    ap.add_argument("--channels", default="0", help="channels to scan, e.g. 0 or 0,1 (default 0)")
    ap.add_argument("--from", dest="start", type=int, default=20, help="first threshold, mV")
    ap.add_argument("--to", dest="stop", type=int, default=400, help="last threshold, mV")
    ap.add_argument("--step", type=int, default=20, help="mV")
    ap.add_argument("--thresholds", help="explicit list instead, e.g. 30,50,80,120")
    ap.add_argument("-t", "--seconds", type=float, default=10, help="seconds per point (default 10)")
    ap.add_argument("-n", "--hits", type=int, help="stop a point after this many hits")
    ap.add_argument("--cal", help="calibration file, or 'none' (default: the nearest master in calibrations/)")
    ap.add_argument("--self", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--short-ns", type=float, default=2.0, help="ToT below this counts as short (default 2)")
    ap.add_argument("--also", help="other channels to set at every point, CH:MV,... (e.g. 2:150)")
    ap.add_argument("-o", "--outdir", help="scan folder (default data/<date>_<time>_threshold_scan)")
    ap.add_argument("--analyse", metavar="DIR", help="analyse an existing scan folder, no board")
    ap.add_argument("--no-analysis", action="store_true",
                    help="only take the data; analyse later with --analyse (for long points on a Pi:"
                         " the analysis keeps every point's hits in memory)")
    args = ap.parse_args()

    if args.analyse:
        analyse_scan(Path(args.analyse), args.cal)
        return
    if not args.host:
        ap.error("give the board address, or --analyse DIR")
    channels = sorted({int(c) for c in args.channels.split(",")})
    if not all(0 <= c < collect_data.TDC_CHANNELS for c in channels):
        ap.error(f"--channels are TDC channels 0 to {collect_data.TDC_CHANNELS - 1}")
    if args.thresholds:
        thresholds = [int(t) for t in args.thresholds.split(",")]
    else:
        thresholds = list(range(args.start, args.stop + 1, args.step))
    if not thresholds or not all(0 <= t <= 3300 for t in thresholds):
        ap.error("thresholds must be 0 to 3300 mV")
    also = {}
    if args.also:
        try:
            also = collect_data.parse_thresholds(args.also)
        except ValueError as e:
            ap.error(f"--also {args.also}: {e}")
        if not isinstance(also, dict) or set(also) & set(channels):
            ap.error("--also takes CH:MV,... for channels that are not scanned")

    out = Path(args.outdir) if args.outdir else collect_data.new_run_dir("threshold_scan")
    out.mkdir(parents=True, exist_ok=True)
    (out / "scan.json").write_text(json.dumps({
        "channels": channels, "thresholds": thresholds, "seconds": args.seconds,
        "hits": args.hits, "self": args.self, "short_ns": args.short_ns, "host": args.host,
        "also": also}, indent=1))
    for i, mv in enumerate(thresholds):
        print(f"\n[scan] point {i + 1} of {len(thresholds)}: {mv} mV on channel(s) {channels}")
        collect_data.capture(args.host, "tdc", {**also, **{ch: mv for ch in channels}}, max_events=args.hits,
                             max_seconds=args.seconds, out_dir=out / f"thr_{mv:04d}")
    if args.no_analysis:
        print(f"\n[scan] done, not analysed: python threshold_scan.py --analyse {out}")
        return
    analyse_scan(out, args.cal)


if __name__ == "__main__":
    main()
