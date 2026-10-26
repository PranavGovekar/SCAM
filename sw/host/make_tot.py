#!/usr/bin/env python3
"""
make_tot.py -- turn the hits.csv of a run into tot.csv: one row per hit with
its channel, time and ToT in ns, calibrated.

    python make_tot.py data/pedestal_39mV data/source_39mV
    python make_tot.py data/2026-10-26_124030_threshold_scan/thr_*     # every point of a scan
    python make_tot.py --master none data/source_39mV                  # raw, equal bins

The calibration is the master (calibrations/master_*.json) nearest the run's
die temperature, or the file given with --master. tot.csv starts with a few
"# key: value" lines that plot_tot.py and plot_tot_pedestal.py read:

    # run: data/source_39mV
    # run_seconds: 600.00 (run_seconds)
    # threshold_mv: 39
    # die_temp_c: 28.1
    # calibration: calibrations/master_2026-10-26_125910_28.6C.json
    channel,time_ns,tot_ns
    0,0.0000,4.7270

time_ns is the rising edge, counted from the clock cycle of the first hit of
the run (so it can start just below 0). All channels share that zero, so
times of different channels compare directly.
"""

import argparse
import sys
from pathlib import Path

import numpy as np

from tdc_analysis import (CLOCK_PERIOD_PS, apply_table, find_master, load_cal, load_hits,
                          raw_table, read_run_info, run_die_temp, run_seconds, tot_ps)


def tables_for(run_dir, master):
    """Calibration tables for a run and the name of where they came from."""
    if master == "none":
        return {}, "raw (equal bins)"
    if master:
        return load_cal(master), master
    found = find_master(run_die_temp(read_run_info(run_dir)))
    if found is None:
        print("  no master calibration in calibrations/, using raw equal bins")
        return {}, "raw (equal bins)"
    return load_cal(found[0]), str(found[0])


def make_tot(run_dir, master):
    run_dir = Path(run_dir)
    hits = load_hits(run_dir)
    info = read_run_info(run_dir)
    seconds, source = run_seconds(info, hits)
    tables, cal_name = tables_for(run_dir, master)

    t0 = hits[:, 1].min() if len(hits) else 0
    rows = []
    print(f"{run_dir}")
    for ch in np.unique(hits[:, 0]):
        h = hits[hits[:, 0] == ch]
        start, stop = tables.get(f"ch{ch}_start"), tables.get(f"ch{ch}_stop")
        if start is None or stop is None:
            start, stop = raw_table(h[:, 2]), raw_table(h[:, 4])
        tot = tot_ps(h, start, stop) / 1000
        time = ((h[:, 1] - t0) * CLOCK_PERIOD_PS - apply_table(start, h[:, 2])) / 1000
        rows.append(np.column_stack([h[:, 0], time, tot]))
        print(f"  ch{ch}: {len(h)} hits, mean ToT {tot.mean():.3f} ns")
    rows = np.concatenate(rows) if rows else np.zeros((0, 3))
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
    ap.add_argument("--master", help="calibration file, or 'none' for raw equal bins "
                                     "(default: the master nearest the die temperature)")
    args = ap.parse_args()
    for run in args.runs:
        if not (Path(run) / "hits.csv").exists():
            print(f"{run}: no hits.csv, skipped", file=sys.stderr)
            continue
        make_tot(run, args.master)


if __name__ == "__main__":
    main()
