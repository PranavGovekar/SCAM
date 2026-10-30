# data

Captures from the board, one folder per run, named `<date>_<time>_<kind>`.
Written by `sw/host/collect_data.py` (`_tdc`, `_ct`), `sw/host/test_tdc.py`
(`_tdc_test`), `sw/host/make_master_cal.py` (`_master_cal`) and
`sw/host/threshold_scan.py` (`_threshold_scan`). Not in git, apart from this
file.

| File | Contents |
| :-- | :-- |
| `hits.csv` | one row per TDC hit or CT event |
| `run.txt` | settings (threshold, limits), run time, board output, packets received |
| `tot.csv` | TDC: time and ToT in ns per hit (`make_tot.py`) |
| `tot_ch<N>*.png` | TDC: ToT plots (`plot_tot.py`) |
| `calibration.json` | TDC test: time of each fine code, per delay line |
| `calibrations/` | TDC: the board's calibrations of the run (`cal_<n>.json`, `--cal-window`) and `self_calibration.json` (`make_self_cal.py`); `make_tot.py` uses them |
| `summary.txt` | TDC test: code ranges, bin widths, DNL/INL, ToT results |
| `plots/ch<N>/` | TDC test: ToT (raw, calibrated, both) and code-density plots |
