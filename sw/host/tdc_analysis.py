"""
tdc_analysis.py -- analysis functions for SCAM TDC captures, shared by the
host scripts (test_tdc.py, threshold_scan.py, make_tot.py, plot_tot.py, ...).

How a hit maps to time (apps/tdc/hw/src): each channel has a start line
(rising edge) and a stop line (falling edge). The fine code is the number of
taps the edge travelled before the next 400 MHz clock edge, so a larger code
means an earlier edge:

    t   = coarse * T - t_line(fine)          T = 2.5 ns
    ToT = (f_coarse - r_coarse) * T - t_stop(f_fine) + t_start(r_fine)

A calibration ("table") gives t_line(k), the time of each fine code. It comes
from a code-density test: with edges at random phase, the number of hits on a
code is proportional to that code's bin width.
"""

import json
import warnings
from pathlib import Path

import numpy as np

CLOCK_PERIOD_PS = 2500.0   # 400 MHz TDC clock
DAC_STEP_MV = 3300 / 255   # threshold DAC: 8 bits over 3.3 V


def dac_mv(requested):
    """The threshold the DAC really sets for a requested value in mV."""
    return int(requested * 255 // 3300) * DAC_STEP_MV


def raw_table(codes):
    """Equal-width bins: the highest code seen spans one clock period."""
    top = max(int(codes.max()), 1)
    return np.arange(top + 1) * CLOCK_PERIOD_PS / top


def code_density(codes):
    """Code-density calibration of one delay line. Returns (table, info)."""
    # np.bincount wants the native index type (32 bits on a Raspberry Pi).
    codes = np.asarray(codes).astype(np.intp)
    counts = np.bincount(codes, minlength=int(codes.max()) + 1).astype(float)
    total = counts.sum()
    table = CLOCK_PERIOD_PS * (np.cumsum(counts) - counts / 2) / total

    used = np.nonzero(counts)[0]
    lo, hi = int(used[0]), int(used[-1])
    span = counts[lo:hi + 1]
    lsb = CLOCK_PERIOD_PS / len(span)
    widths = CLOCK_PERIOD_PS * span / total
    dnl = widths / lsb - 1
    info = {
        "hits": int(total), "codes": [lo, hi], "lsb_ps": lsb,
        "counts": span, "widths": widths, "dnl": dnl, "inl": np.cumsum(dnl),
        "empty": int(np.count_nonzero(span == 0)),
    }
    return table, info


def apply_table(table, codes):
    """Time in ps of each code; codes past the end of the table count as one period."""
    return np.where(codes < len(table),
                    table[np.minimum(codes, len(table) - 1)], CLOCK_PERIOD_PS)


def tot_ps(hits, t_start, t_stop):
    _, r_coarse, r_fine, f_coarse, f_fine = hits.T
    return ((f_coarse - r_coarse) * CLOCK_PERIOD_PS
            - apply_table(t_stop, f_fine) + apply_table(t_start, r_fine))


def peak_stats(tot, bin_ps):
    """Mean, RMS, Gaussian sigma (fit to the log of the peak) and FWHM, in ps."""
    mean, rms = float(tot.mean()), float(tot.std())
    lo, hi = np.percentile(tot, [0.5, 99.5])
    edges = np.arange(lo, hi + bin_ps, bin_ps)
    counts, edges = np.histogram(tot, bins=edges)
    centres = (edges[:-1] + edges[1:]) / 2
    sigma, mu = rms, mean
    peak = counts.max() if len(counts) else 0
    sel = counts > 0.05 * peak
    if sel.sum() >= 3:
        # log(counts) of a Gaussian is a parabola: a x^2 + b x + c
        x = centres[sel] - mean
        a, b, _ = np.polyfit(x, np.log(counts[sel]), 2, w=np.sqrt(counts[sel]))
        if a < 0:
            sigma = float(np.sqrt(-1 / (2 * a)))
            mu = float(mean - b / (2 * a))
    fwhm = float("nan")
    above = np.nonzero(counts >= peak / 2)[0]
    if len(above) and 0 < above[0] and above[-1] < len(counts) - 1:
        # Interpolate where the histogram crosses half the peak on each side.
        half = peak / 2
        i, j = above[0], above[-1]
        left = np.interp(half, [counts[i - 1], counts[i]], [centres[i - 1], centres[i]])
        right = np.interp(half, [counts[j + 1], counts[j]], [centres[j + 1], centres[j]])
        fwhm = float(right - left)
    return {"hits": len(tot), "mean": mean, "rms": rms, "sigma": sigma, "mu": mu, "fwhm": fwhm}


# ---------------------------------------------------------------- calibrations

MASTER_DIR = Path(__file__).resolve().parents[2] / "calibrations"


def load_cal(path):
    """Tables {line name: t_ps array} of a calibration file (collect_data's
    calibrations/cal_<n>.json, test_tdc.py's calibration.json, or a master)."""
    with open(path) as f:
        cal = json.load(f)
    return {name: np.array(line["t_ps"]) for name, line in cal["lines"].items()}


def find_master(temp_c=None, folder=MASTER_DIR):
    """The master calibration nearest temp_c (the newest if temp_c is None).
    Returns (path, its die temperature, temp_c - that temperature), or None."""
    masters = []
    for path in sorted(Path(folder).glob("master_*.json")):
        try:
            with open(path) as f:
                masters.append((path, json.load(f).get("die_temp_c")))
        except (OSError, ValueError):
            continue
    if not masters:
        return None
    if temp_c is None:
        path, t = masters[-1]
    else:
        path, t = min(masters, key=lambda m: abs(temp_c - m[1]) if m[1] is not None else 1e9)
    return path, t, (None if temp_c is None or t is None else temp_c - t)


def read_run_info(run_dir):
    """The "key: value" lines at the top of a run's run.txt, as a dict."""
    info = {}
    path = Path(run_dir) / "run.txt"
    if path.exists():
        for line in path.read_text().splitlines():
            if ": " in line and not line.startswith(" "):
                key, value = line.split(": ", 1)
                info.setdefault(key, value)
    return info


def run_die_temp(info):
    """Mean of die_temp_start_c and die_temp_end_c in a run's info, or None."""
    temps = []
    for key in ("die_temp_start_c", "die_temp_end_c"):
        try:
            temps.append(float(info.get(key, "")))
        except ValueError:
            pass
    return sum(temps) / len(temps) if temps else None


# ---------------------------------------------------------------- run files

def load_hits(run_dir):
    """A run's hits.csv as an (N, 5) int64 array, all channels."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")      # a run without hits: empty file
        data = np.loadtxt(Path(run_dir) / "hits.csv", delimiter=",", skiprows=1,
                          dtype=np.int64, ndmin=2)
    if data.size == 0:
        return np.zeros((0, 5), dtype=np.int64)
    return data


def run_seconds(info, hits=None):
    """How long the board took data, and where that number came from.
    run_seconds in run.txt is measured by collect_data.py; older runs only
    have the requested -t, which is right unless -n stopped the run first;
    failing both, the span of the rising edges (too short at low rates:
    bitstreams without the end-of-run flush send only whole packets of 90
    hits)."""
    try:
        return float(info.get("run_seconds", "")), "run_seconds"
    except ValueError:
        pass
    try:
        stopped_by_n = int(info.get("rows_saved", 0)) >= int(info.get("max_events", ""))
    except ValueError:
        stopped_by_n = False
    if not stopped_by_n:
        try:
            return float(info.get("max_seconds", "")), "max_seconds"
        except ValueError:
            pass
    if hits is not None and len(hits) > 1:
        return float(hits[:, 1].max() - hits[:, 1].min()) * CLOCK_PERIOD_PS * 1e-12, "hit span"
    return None, "unknown"


def threshold_of(text, channel):
    """Requested threshold (mV) of channel from a threshold_mv entry such as
    "250" or "0:120,1:150"; None if it is not there."""
    try:
        if ":" in text:
            return float(dict(item.split(":") for item in text.split(","))[str(channel)])
        return float(text)
    except (KeyError, ValueError):
        return None


def read_tot(path):
    """A tot.csv from make_tot.py: (header dict, array of channel, time_ns, tot_ns).
    path may also be the run folder. header["seconds"] is the run time as a
    number, None if unknown."""
    path = Path(path)
    if path.is_dir():
        path = path / "tot.csv"
    header, comments = {}, 0
    with open(path) as f:
        for line in f:
            if not line.startswith("#"):
                break
            comments += 1
            if ": " in line:
                key, value = line[1:].strip().split(": ", 1)
                header[key] = value
    try:
        header["seconds"] = float(header.get("run_seconds", "").split()[0])
    except (IndexError, ValueError):
        header["seconds"] = None
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")      # a run without hits
        # skip the # lines and the column names
        data = np.loadtxt(path, delimiter=",", skiprows=comments + 1, ndmin=2)
    if data.size == 0:
        data = np.zeros((0, 3))
    return header, data
