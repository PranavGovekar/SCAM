#!/usr/bin/env python3
"""
make_self_cal.py -- code-density calibration from a run's own hits.

    python make_self_cal.py data/run_a
    python make_self_cal.py data/run_a data/run_b          # each run on its own

For every delay line (start and stop of each channel) the number of hits on
each fine code is proportional to that code's width, if the hits arrive at
random times: detector pulses do, a generator locked near a multiple of the
TDC clock does not. The tables are saved as

    <run>/calibrations/self_calibration.json

in the format of every other calibration file, and make_tot.py uses it for
that run before anything else. Delete the file to go back to the run's board
calibrations or a master.

A line is only calibrated well with enough hits (at least about 50 per code,
some 30000 per line) and with no empty codes inside its range: both are
checked and reported. Channels with fewer than 1000 hits are left out.
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

from tdc_analysis import CLOCK_PERIOD_PS, SELF_CAL_NAME, code_density, load_hits

MIN_CHANNEL_HITS = 1000    # channels with fewer hits are left out
MIN_HITS_PER_CODE = 50     # below this the code-density table is noisy
MAX_EMPTY_FRACTION = 0.10  # more empty codes than this: arrival phases not random


def make_self_cal(run_dir):
    run_dir = Path(run_dir)
    hits = load_hits(run_dir)
    print(f"{run_dir}: {len(hits)} hits")
    cal = {"clock_period_ps": CLOCK_PERIOD_PS, "source": "self", "run": str(run_dir),
           "date": f"{datetime.now():%Y-%m-%d %H:%M:%S}", "lines": {}}
    for ch in sorted(int(c) for c in set(hits[:, 0])):
        h = hits[hits[:, 0] == ch]
        if len(h) < MIN_CHANNEL_HITS:
            print(f"  ch{ch}: {len(h)} hits, too few, left out")
            continue
        for line, codes in (("start", h[:, 2]), ("stop", h[:, 4])):
            table, info = code_density(codes)
            lo, hi = info["codes"]
            n_codes = hi - lo + 1
            notes = []
            if info["hits"] / n_codes < MIN_HITS_PER_CODE:
                notes.append(f"only {info['hits'] / n_codes:.0f} hits per code")
            if info["empty"] > MAX_EMPTY_FRACTION * n_codes:
                notes.append(f"{info['empty']} of {n_codes} codes empty: the hits may not "
                             f"arrive at random times")
            cal["lines"][f"ch{ch}_{line}"] = {
                "hits": info["hits"], "codes": [lo, hi], "empty": info["empty"],
                "t_ps": [round(float(t), 3) for t in table]}
            print(f"  ch{ch} {line:5}: {info['hits']} hits, codes {lo}..{hi}, "
                  f"{info['empty']} empty, mean bin {info['lsb_ps']:.2f} ps"
                  + "".join(f"\n    WARNING: {n}" for n in notes))
    if not cal["lines"]:
        print("  nothing calibrated, no file written")
        return
    out = run_dir / "calibrations" / SELF_CAL_NAME
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(cal))
    print(f"  -> {out}")


def main():
    ap = argparse.ArgumentParser(description="Code-density calibration from a run's own hits")
    ap.add_argument("runs", nargs="+", help="run folders (with hits.csv)")
    args = ap.parse_args()
    for run in args.runs:
        if not (Path(run) / "hits.csv").exists():
            sys.exit(f"ERROR: no hits.csv in {run}")
        make_self_cal(run)


if __name__ == "__main__":
    main()
