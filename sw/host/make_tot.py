#!/usr/bin/env python3
"""
make_tot.py -- turn the hits.csv of a run into tot.csv: one row per hit with
its channel, time and ToT in ns.

    python make_tot.py data/run_a data/run_b                        # calibration found as below
    python make_tot.py data/<date>_threshold_scan/thr_*             # every point of a scan
    python make_tot.py --cal calibrations/master_<...>.json data/run_a
    python make_tot.py --cal none data/run_a                        # equal bins

The calibration is, in this order, the first that exists:
    <run>/calibrations/self_calibration.json   from make_self_cal.py, for every hit
    <run>/calibrations/cal_<n>.json            the run's board calibrations
                                               (collect_data.py --cal-window); each
                                               from the hit it was taken before,
                                               the first also for the hits before it
    calibrations/master_*.json                 the master nearest the run's die
                                               temperature (make_master_cal.py)
    nothing                                    every fine code an equal bin
--cal FILE or FOLDER uses that instead, --cal none equal bins. A channel the
calibration has no table for gets equal bins, with a warning. One tot.csv per
run, whatever the number of calibrations.

tot.csv starts with a few "# key: value" lines that plot_tot.py reads:

    # run: data/run_a
    # run_seconds: 600.00 (run_seconds)
    # threshold_mv: 100
    # die_temp_c: 28.1
    # calibration: calibrations/ of the run: cal_000.json from row 0, cal_001.json from row 2482920
    channel,time_ns,tot_ns
    0,0.0000,4.7270

Rows are in time order, all channels together. time_ns is the rising edge,
counted from the clock cycle of the first hit of the run (so it can start just
below 0). All channels share that zero, so times of different channels compare
directly.
"""

import argparse
import sys
from pathlib import Path

import numpy as np

from tdc_analysis import (CLOCK_PERIOD_PS, apply_table, load_hits, run_calibration,
                          raw_table, read_run_info, run_die_temp, run_seconds, tot_ps)


def make_tot(run_dir, cal):
    run_dir = Path(run_dir)
    hits = load_hits(run_dir)
    info = read_run_info(run_dir)
    seconds, source = run_seconds(info, hits)
    segments, cal_name = run_calibration(run_dir, cal)
    # Which calibration each hit row uses: the last one taken before it.
    seg_of_row = np.zeros(len(hits), dtype=int)
    for k, (row, _, _) in enumerate(segments[1:], start=1):
        seg_of_row[row:] = k

    t0 = hits[:, 1].min() if len(hits) else 0
    rows = []
    print(f"{run_dir}")
    print(f"  calibration: {cal_name}")
    for ch in np.unique(hits[:, 0]):
        sel = hits[:, 0] == ch
        h, seg = hits[sel], seg_of_row[sel]
        raw = (raw_table(h[:, 2]), raw_table(h[:, 4]))
        tot = np.empty(len(h))
        time = np.empty(len(h))
        for k in np.unique(seg) if segments else [None]:
            part = seg == k if k is not None else np.ones(len(h), dtype=bool)
            tables = segments[k][1] if k is not None else {}
            start, stop = tables.get(f"ch{ch}_start"), tables.get(f"ch{ch}_stop")
            if start is None or stop is None:
                if k is not None:
                    print(f"  WARNING: {segments[k][2]} has no table for ch{ch}, equal bins used")
                start, stop = raw
            p = h[part]
            tot[part] = tot_ps(p, start, stop) / 1000
            time[part] = ((p[:, 1] - t0) * CLOCK_PERIOD_PS - apply_table(start, p[:, 2])) / 1000
        rows.append(np.column_stack([h[:, 0], time, tot]))
        print(f"  ch{ch}: {len(h)} hits, mean ToT {tot.mean():.3f} ns")
    rows = np.concatenate(rows) if rows else np.zeros((0, 3))
    rows = rows[np.argsort(rows[:, 1], kind="stable")]
    if seconds is None:
        print("  WARNING: run time unknown, rates cannot be computed")
    elif source != "run_seconds":
        print(f"  note: run time {seconds:.2f} s taken from {source}")

    out = run_dir / "tot.csv"
    with open(out, "w") as f:
        f.write(f"# run: {run_dir}\n")
        f.write(f"# run_seconds: {'unknown' if seconds is None else f'{seconds:.2f}'} ({source})\n")
        f.write(f"# threshold_mv: {info.get('threshold_mv', 'unknown')}\n")
        temp = run_die_temp(info)
        f.write(f"# die_temp_c: {'unknown' if temp is None else f'{temp:.1f}'}\n")
        f.write(f"# calibration: {cal_name}\n")
        f.write("channel,time_ns,tot_ns\n")
        np.savetxt(f, rows, fmt=["%d", "%.4f", "%.4f"], delimiter=",")
    print(f"  -> {out}")


def main():
    ap = argparse.ArgumentParser(description="hits.csv -> tot.csv (time and ToT in ns)")
    ap.add_argument("runs", nargs="+", help="run folders (with hits.csv)")
    ap.add_argument("--cal", help="calibration file or folder to use instead, or 'none' for "
                                  "equal bins (default: the run's own, else the nearest master)")
    args = ap.parse_args()
    for run in args.runs:
        if not (Path(run) / "hits.csv").exists():
            print(f"{run}: no hits.csv, skipped", file=sys.stderr)
            continue
        make_tot(run, args.cal)


if __name__ == "__main__":
    main()
