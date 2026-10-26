# data

Captures from the board, one folder per run, named `<date>_<time>_<kind>`.
Written by `sw/host/collect_data.py` (`_tdc`, `_ct`),
`sw/host/test_tdc.py` (`_tdc_test`) and `sw/host/test_tdc_cal_hits.py`
(`_tdc_cal_hits`). Not in git, apart from this file.

| File | Contents |
| :-- | :-- |
| `hits.csv` | one row per TDC hit or CT event |
| `run.txt` | settings (threshold, limits), run time, board output, packets received |
| `tot.csv` | TDC: time and ToT in ns per hit (`make_tot.py`) |
| `tot_ch<N>*.png` | TDC: ToT plots (`plot_tot.py`, `plot_tot_pedestal.py`) |
| `calibration.json` | TDC test: time of each fine code, per delay line |
| `summary.txt` | TDC test: code ranges, bin widths, DNL/INL, ToT results |
| `plots/ch<N>/` | TDC test: ToT (raw, calibrated, both) and code-density plots |
| `cal_hits/` | calibration-hits test: `summary.txt`, `results.csv`, `plots/` |
