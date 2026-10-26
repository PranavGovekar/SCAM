#!/usr/bin/env python3
"""
make_master_cal.py -- one long board calibration, kept as a master calibration.

The board switches its calibration input (FMC DIO card channel 4, a
free-running generator near 100 MHz) onto every channel for --window seconds
and sends one code-density table per delay line. The tables are saved, with
the PL die temperature, as

    calibrations/master_<date>_<time>_<temp>C.json

in the format test_tdc.py --cal reads. The analysis scripts pick the master
nearest the die temperature of a run (tdc_analysis.find_master): the tables
change by about 0.5 ps per C.

The gate passes one generator pulse in 256 per channel: about 380 k hits per
line per second at 97 MHz, a little fewer with 4 channels (the readout limit
is about 1.5 M records/s). 270 s gives about 100 million hits per line.
Let the board warm up first (30 min or more after power-up).

    python make_master_cal.py -v 4:200 data-yeeter.local            # 270 s
    python make_master_cal.py -v 4:200 --window 60 data-yeeter.local

-v sets the thresholds as in collect_data.py; 4:<mV> (2:<mV> with the
2-channel bitstream) sets only the calibration input and leaves the signal
channels as they are.
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import collect_data

MASTER_DIR = Path(__file__).resolve().parents[2] / "calibrations"
FLAG_EMPTY = 0x002
FLAG_RANGE = 0x008


def main():
    ap = argparse.ArgumentParser(description="Take a long board calibration and keep it as a master")
    ap.add_argument("host", help="board address, e.g. data-yeeter.local")
    ap.add_argument("-v", "--threshold", required=True, metavar="MV",
                    help="threshold for every channel, or CH:MV,... (4 = calibration input)")
    ap.add_argument("--window", type=float, default=270, help="calibration window in s (default 270)")
    ap.add_argument("--note", default="", help="free text stored with the master")
    args = ap.parse_args()
    try:
        threshold = collect_data.parse_thresholds(args.threshold)
    except ValueError as e:
        ap.error(f"-v {args.threshold}: {e}")

    run_dir = collect_data.new_run_dir("master_cal")
    temp_before = collect_data.read_die_temp(args.host)
    # No physics hits are wanted: the board runs until -t, a little longer
    # than the window.
    collect_data.capture(args.host, "tdc", threshold, max_seconds=args.window + 10,
                         out_dir=run_dir, cal_window=args.window)
    temp_after = collect_data.read_die_temp(args.host)

    cal_path = run_dir / "calibrations" / "cal_000.json"
    if not cal_path.exists():
        sys.exit(f"ERROR: no calibration arrived (see {run_dir / 'run.txt'}). "
                 "Is the generator on card channel 4 and the threshold below its amplitude?")
    cal = json.loads(cal_path.read_text())
    problems = []
    for name, line in cal["lines"].items():
        if line["flags"] & (FLAG_EMPTY | FLAG_RANGE):
            problems.append(f"{name} ({', '.join(line['flag_names'])})")
    if not cal["lines"]:
        problems.append("no line has hits")
    if problems:
        sys.exit(f"ERROR: not saved as a master, bad lines: {', '.join(problems)} "
                 f"(the calibration is in {cal_path})")

    temps = [t for t in (temp_before, temp_after) if t is not None]
    temp = sum(temps) / len(temps) if temps else None
    cal.update({
        "master": True,
        "date": f"{datetime.now():%Y-%m-%d %H:%M:%S}",
        "die_temp_c": None if temp is None else round(temp, 2),
        "die_temp_before_c": temp_before, "die_temp_after_c": temp_after,
        "window_s": args.window,
        "threshold_mv": collect_data.format_thresholds(threshold),
        "source_run": str(run_dir),
        "note": args.note,
    })
    MASTER_DIR.mkdir(exist_ok=True)
    tag = "unknownC" if temp is None else f"{temp:.1f}C"
    out = MASTER_DIR / f"master_{datetime.now():%Y-%m-%d_%H%M%S}_{tag}.json"
    out.write_text(json.dumps(cal))
    print(f"\nmaster calibration: {out}")
    print(f"  die temperature {tag}, window {args.window:g} s")
    for name, line in cal["lines"].items():
        lo, hi = line["codes"]
        print(f"  {name}: {line['hits']:,} hits, codes {lo}..{hi}, {line['empty']} empty")
    if cal.get("incomplete"):
        # Lines without hits: channels the loaded bitstream does not have, or a
        # calibration packet lost on the way.
        print(f"  not in this master: {', '.join(cal['incomplete'])} (no hits, or a lost packet)")


if __name__ == "__main__":
    main()
