#!/usr/bin/env python3
"""
collect_data.py -- SCAM host collector.

Starts yeet-data-tdc or yeet-data-ct on the board over SSH, receives its UDP
packets and saves them as CSV in a run folder under data/.

Usage:
    python collect_data.py -v 250 -n 18000 data-yeeter.local
    python collect_data.py --app ct -v 1000 -t 60 data-yeeter.local
    python collect_data.py --no-ssh -t 30 data-yeeter.local   # board program started by hand
    python collect_data.py -v 250 -n 1000000 --cal-window 1 data-yeeter.local  # calibrate first

The input threshold (-v, millivolts) is required: the FMC DIO card powers up
with its threshold at 0 V and then sees no pulses.

A run folder (data/<date>_<time>_<app>/ by default) holds:
    hits.csv   one row per TDC hit or CT event
    run.txt    settings, the board program's output and packet counts
    calibrations/cal_<n>.json   TDC only, one per calibration the board sent
"""

import argparse
import json
import math
import os
import socket
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import numpy as np

SSH_USER = "petalinux"
SSH_PASS = "petalinux"
APPS = {"tdc": "yeet-data-tdc", "ct": "yeet-data-ct"}
UDP_PORT = 8080
# Time allowed for packets still in flight after the board program exits.
DRAIN_S = 1.0
# A burst of TDC packets easily exceeds the default socket buffer.
RECV_BUFFER_BYTES = 8 * 1024 * 1024
POLL_TIMEOUT_S = 2.0
PACKET_BYTES = {"tdc": 1440, "ct": 8}
EVENTS_PER_PACKET = {"tdc": 90, "ct": 1}
# Packets decoded per step when the raw capture is converted to CSV.
DECODE_CHUNK_PACKETS = 20000

DATA_DIR = Path(__file__).resolve().parents[2] / "data"

TDC_COLUMNS = ["Channel_ID", "Rising_Coarse", "Rising_Fine", "Falling_Coarse", "Falling_Fine"]
CT_COLUMNS = ["Timestamp", "Coinc_Out", "ABCD", "BCD", "ACD", "ABD", "ABC",
              "CD", "BD", "BC", "AD", "AC", "AB", "D", "C", "B", "A"]

_MASK48 = np.uint64((1 << 48) - 1)

# TDC calibration words (yeet-data-tdc.c), bits 127:120 of a word with bit 127 set.
WORD_CAL_HEADER = 0xC1
WORD_CAL_TABLE = 0xC2
CLOCK_PERIOD_PS = 2500.0
TABLE_UNIT_PS = 1 / 16
TABLE_PER_WORD = 6
LINE_NAMES = ["ch0_start", "ch0_stop", "ch1_start", "ch1_stop",
              "ch2_start", "ch2_stop", "ch3_start", "ch3_stop"]
CAL_FLAGS = {0x001: "few hits", 0x002: "empty codes", 0x004: "wide bins",
             0x008: "code range", 0x010: "calibration hits dropped"}


def tdc_words(buf):
    """The 128-bit words of TDC packets as (low, high) 64-bit halves, and a
    mask of the physics hits (bit 127 clear)."""
    w = np.frombuffer(buf, dtype="<u8").reshape(-1, 2)
    return w, (w[:, 1] >> np.uint64(63)) == 0


def parse_tdc(buf):
    """Decode TDC packets into rows of (channel, rising coarse, rising fine,
    falling coarse, falling fine). Calibration and padding words are skipped.

    Each hit is the 128-bit word that tdc_channel.vhd writes to its FIFO,
    sent least significant byte first:

        [9:0]     rising fine    (delay-line bin, 0..784)
        [57:10]   rising coarse  (400 MHz counter)
        [67:58]   falling fine
        [115:68]  falling coarse
        [127:116] channel id (bit 127 set: not a hit, see decode_calibrations)
    """
    w, physics = tdc_words(buf)
    w = w[physics]
    lo, hi = w[:, 0], w[:, 1]
    rows = np.empty((len(w), 5), dtype=np.int64)
    rows[:, 0] = hi >> np.uint64(52)
    rows[:, 1] = (lo >> np.uint64(10)) & _MASK48
    rows[:, 2] = lo & np.uint64(0x3FF)
    rows[:, 3] = (hi >> np.uint64(4)) & _MASK48
    rows[:, 4] = (lo >> np.uint64(58)) | ((hi & np.uint64(0xF)) << np.uint64(6))
    return rows


def decode_calibrations(words):
    """Rebuild the calibrations from the calibration words, in arrival order.

    words: (low, high, hit rows before the word). yeet-data-tdc.c sends per
    delay line one header word, then the table words:

        header  [127:120] 0xC1, [119:112] calibration id, [111:108] line
                (0 ch0 start, 1 ch0 stop, 2 ch1 start, 3 ch1 stop),
                [107:96] flags, [95:64] hits, [63:54] first code,
                [53:44] last code, [43:34] empty codes, [33:24] wide codes,
                [23:16] table words, [15:0] window in ms
        table   [127:120] 0xC2, [119:112] id, [111:108] line, [107:98] first
                code, [95:0] six u16: bin-centre time of that code and the
                next five, in 1/16 ps

    Returns a list of calibrations in the format test_tdc.py --cal reads,
    plus flags and counts. A line with table words missing (a lost packet)
    is listed under "incomplete" instead of "lines".
    """
    cals = []
    cur = None
    for lo, hi, row in words:
        kind, cal_id, line = hi >> 56, (hi >> 48) & 0xFF, (hi >> 44) & 0xF
        if kind not in (WORD_CAL_HEADER, WORD_CAL_TABLE) or line >= len(LINE_NAMES):
            continue
        if kind == WORD_CAL_HEADER:
            if cur is None or cur["board_cal_id"] != cal_id or LINE_NAMES[line] in cur["_lines"]:
                cur = {"clock_period_ps": CLOCK_PERIOD_PS, "source": "board",
                       "board_cal_id": cal_id, "first_hit_row": int(row),
                       "window_ms": int(lo & 0xFFFF), "_lines": {}}
                cals.append(cur)
            code_lo, code_hi = int((lo >> 54) & 0x3FF), int((lo >> 44) & 0x3FF)
            flags = int((hi >> 32) & 0xFFF)
            cur["_lines"][LINE_NAMES[line]] = {
                "hits": int(hi & 0xFFFFFFFF), "codes": [code_lo, code_hi],
                "flags": flags, "flag_names": [n for b, n in CAL_FLAGS.items() if flags & b],
                "empty": int((lo >> 34) & 0x3FF), "wide": int((lo >> 24) & 0x3FF),
                "_words": int((lo >> 16) & 0xFF), "_t": {},
            }
        elif cur is not None and cur["board_cal_id"] == cal_id and LINE_NAMES[line] in cur["_lines"]:
            entry = cur["_lines"][LINE_NAMES[line]]
            first = int((hi >> 34) & 0x3FF)
            values = [(lo >> (16 * j)) & 0xFFFF for j in range(4)] + \
                     [(hi >> (16 * j)) & 0xFFFF for j in range(2)]
            for j, v in enumerate(values):
                if first + j <= entry["codes"][1]:
                    entry["_t"][first + j] = v * TABLE_UNIT_PS

    for cal in cals:
        cal["lines"], cal["incomplete"] = {}, []
        for name, entry in cal.pop("_lines").items():
            code_lo, code_hi = entry["codes"]
            t = entry.pop("_t")
            entry.pop("_words")
            if entry["hits"] == 0 or len(t) != code_hi - code_lo + 1:
                cal["incomplete"].append(name)
                continue
            # Index = fine code, as test_tdc.py builds it; codes below the
            # first one seen take 0.
            entry["t_ps"] = [0.0] * code_lo + [t[k] for k in range(code_lo, code_hi + 1)]
            cal["lines"][name] = entry
        # The board sends every line; one whose header word was lost is missing.
        cal["incomplete"] += [n for n in LINE_NAMES
                              if n not in cal["lines"] and n not in cal["incomplete"]]
    return cals


def parse_ct(buf):
    """Decode CT packets: one 64-bit event each, {timestamp[47:0], coinc[15:0]},
    as four_fold_coincidence.vhd writes it. Rows are the timestamp, the 16-bit
    coincidence word, then its bits 14 down to 0 (see CT_COLUMNS)."""
    ev = np.frombuffer(buf, dtype="<u8")
    co = ev & np.uint64(0xFFFF)
    rows = np.empty((len(ev), 17), dtype=np.int64)
    rows[:, 0] = (ev >> np.uint64(16)) & _MASK48
    rows[:, 1] = co
    for col, bit in enumerate(range(14, -1, -1), start=2):
        rows[:, col] = (co >> np.uint64(bit)) & np.uint64(1)
    return rows


def new_run_dir(tag):
    """Create and return data/<YYYY-MM-DD_HHMMSS>_<tag>/."""
    path = DATA_DIR / f"{datetime.now():%Y-%m-%d_%H%M%S}_{tag}"
    path.mkdir(parents=True, exist_ok=False)
    return path


def local_ip_for(host):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((host, 22))
        return s.getsockname()[0]
    except OSError as e:
        sys.exit(f"ERROR: no network route to {host} ({e}). "
                 "Check the cable and the board address.")
    finally:
        s.close()


def listen(local_ip, raw_path, app, stop_event, max_events, stats):
    """Write every packet of the expected size to raw_path, unchanged.
    Decoding waits until the run is over so that no time is lost here."""
    size = PACKET_BYTES[app]
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, RECV_BUFFER_BYTES)
    try:
        sock.bind((local_ip, UDP_PORT))
    except OSError as e:
        print(f"FATAL: cannot bind {local_ip}:{UDP_PORT}: {e}")
        os._exit(1)
    sock.settimeout(POLL_TIMEOUT_S)

    max_packets = math.ceil(max_events / EVENTS_PER_PACKET[app]) if max_events else None
    with open(raw_path, "wb") as f:
        while not stop_event.is_set():
            try:
                data = sock.recv(2048)
            except socket.timeout:
                continue
            if len(data) != size:
                stats["ignored"] += 1
                continue
            f.write(data)
            stats["packets"] += 1
            if stats["packets"] == 1:
                print(f"[data] {app.upper()} packets arriving")
            # TDC calibration packets hold only words with bit 127 set; they
            # do not count towards the hits asked for.
            if app == "tdc" and data[15] & 0x80:
                stats["cal_packets"] += 1
                continue
            if max_packets and stats["packets"] - stats["cal_packets"] >= max_packets:
                stop_event.set()
    sock.close()


def raw_to_csv(raw_path, csv_path, app, max_events):
    """Decode the raw capture in chunks and write the CSV. Returns the row
    count and the TDC calibration words as (low, high, rows before it)."""
    size = PACKET_BYTES[app]
    parse = parse_tdc if app == "tdc" else parse_ct
    rows_written = 0
    cal_words = []
    with open(raw_path, "rb") as src, open(csv_path, "w") as dst:
        dst.write(",".join(TDC_COLUMNS if app == "tdc" else CT_COLUMNS) + "\n")
        while True:
            buf = src.read(size * DECODE_CHUNK_PACKETS)
            if not buf:
                break
            if app == "tdc":
                w, physics = tdc_words(buf)
                idx = np.nonzero(~physics)[0]
                before = rows_written + np.cumsum(physics)[idx]
                cal_words += [(int(w[i, 0]), int(w[i, 1]), int(b)) for i, b in zip(idx, before)]
            rows = parse(buf)
            if max_events:
                rows = rows[:max_events - rows_written]
            np.savetxt(dst, rows, fmt="%d", delimiter=",")
            rows_written += len(rows)
            if max_events and rows_written >= max_events:
                break
    return rows_written, cal_words


def save_calibrations(out_dir, cal_words):
    """Write calibrations/cal_<n>.json and return summary lines for run.txt."""
    cals = decode_calibrations(cal_words)
    if not cals:
        return []
    folder = out_dir / "calibrations"
    folder.mkdir(exist_ok=True)
    lines = []
    for n, cal in enumerate(cals):
        path = folder / f"cal_{n:03d}.json"
        with open(path, "w") as f:
            json.dump(cal, f)
        lines.append(f"calibration {n}: {path.name}, before hit row {cal['first_hit_row']}, "
                     f"window {cal['window_ms']} ms")
        for name, line in cal["lines"].items():
            lo, hi = line["codes"]
            flags = ", ".join(line["flag_names"]) or "ok"
            lines.append(f"  {name}: {line['hits']} hits, codes {lo}..{hi}, "
                         f"{line['empty']} empty, {line['wide']} wide -- {flags}")
        for name in cal["incomplete"]:
            lines.append(f"  {name}: incomplete (no hits, or a calibration packet was lost)")
    return lines


def trigger_remote(host, user, password, cmd):
    """Run cmd on the board, show its output, and return the output lines."""
    lines = []
    try:
        import paramiko
    except ImportError:
        print("ERROR: paramiko not installed. pip install -r requirements.txt")
        return lines

    def show(line):
        line = line.rstrip()
        if line.strip() == password:      # the terminal echoes the sudo password
            return
        lines.append(line)
        print(f"[board] {line}")

    try:
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(host, username=user, password=password)
        print(f"[ssh] {cmd}")
        stdin, stdout, stderr = c.exec_command(cmd, get_pty=True)
        stdin.write(password + "\n")
        stdin.flush()
        try:
            for line in stdout:
                show(line)
        except KeyboardInterrupt:
            # Pass the Ctrl+C on to the board program so it stops cleanly, and
            # show the summary it prints on the way out.
            print("[ssh] stopping the board program")
            stdin.write("\x03")
            stdin.flush()
            for line in stdout:
                show(line)
        c.close()
    except Exception as e:
        print(f"[ssh error] {e}")
    return lines


def board_packets_sent(lines):
    """The 'Packets sent' count from yeet-data-tdc's summary, or None."""
    for line in lines:
        if line.strip().startswith("Packets sent"):
            try:
                return int(line.split(":")[1])
            except (IndexError, ValueError):
                return None
    return None


def capture(host, app="tdc", threshold_mv=None, max_events=None, max_seconds=None,
            out_dir=None, user=SSH_USER, password=SSH_PASS, no_ssh=False,
            cal_window=None, cal_every=None):
    """Run one capture. Returns (run folder, CSV path, rows saved).
    cal_window/cal_every (seconds, TDC): calibrate first, and repeat."""
    out_dir = Path(out_dir) if out_dir else new_run_dir(app)
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "hits.csv"
    raw_path = out_dir / "hits.raw"

    local_ip = local_ip_for(host)
    print(f"Local IP : {local_ip}")
    print(f"Run      : {out_dir}")

    stop_event = threading.Event()
    stats = {"packets": 0, "cal_packets": 0, "ignored": 0}
    listener = threading.Thread(
        target=listen, args=(local_ip, raw_path, app, stop_event, max_events, stats), daemon=True)
    listener.start()
    started = datetime.now()

    board_lines = []
    cmd = None
    if no_ssh:
        # Just listen until max-seconds, max-events or Ctrl+C
        try:
            deadline = time.time() + max_seconds if max_seconds else None
            while listener.is_alive() and not stop_event.is_set():
                if deadline and time.time() >= deadline:
                    break
                time.sleep(0.2)
        except KeyboardInterrupt:
            pass
        stop_event.set()
    else:
        # -p '' keeps sudo's prompt out of the output; the password is sent on
        # stdin by trigger_remote.
        cmd = f"sudo -S -p '' {APPS[app]}"
        if max_events:
            cmd += f" -n {max_events}"
        if max_seconds:
            # The board program takes whole seconds, at least 1.
            cmd += f" -t {max(1, math.ceil(max_seconds))}"
        if threshold_mv is not None:
            cmd += f" -v {threshold_mv}"
        if cal_window:
            cmd += f" -c {cal_window:g}"
        if cal_every:
            cmd += f" -C {cal_every:g}"
        cmd += f" {local_ip}"
        try:
            board_lines = trigger_remote(host, user, password, cmd)
            # The board program has exited: let the last packets arrive.
            listener.join(timeout=DRAIN_S)
        except KeyboardInterrupt:
            pass
        stop_event.set()

    # The listener wakes at least every POLL_TIMEOUT_S to see stop_event.
    listener.join(timeout=POLL_TIMEOUT_S + 3.0)

    print("[data] decoding")
    rows, cal_words = raw_to_csv(raw_path, csv_path, app, max_events)
    raw_path.unlink()
    cal_lines = save_calibrations(out_dir, cal_words)

    sent = board_packets_sent(board_lines)
    received = stats["packets"]
    loss = ""
    if sent:
        loss = f" of {sent} sent ({100.0 * (sent - min(received, sent)) / sent:.1f} % lost)"
    with open(out_dir / "run.txt", "w") as f:
        f.write(f"date: {started:%Y-%m-%d %H:%M:%S}\n")
        f.write(f"command: {' '.join(sys.argv)}\n")
        f.write(f"host: {host}\n")
        f.write(f"app: {app}\n")
        f.write(f"threshold_mv: {threshold_mv if threshold_mv is not None else 'not set'}\n")
        f.write(f"max_events: {max_events or 'none'}\n")
        f.write(f"max_seconds: {max_seconds or 'none'}\n")
        if cmd:
            f.write(f"board_command: {cmd}\n")
        if cal_window:
            f.write(f"calibration: {cal_window:g} s window"
                    + (f", every {cal_every:g} s" if cal_every else ", once") + "\n")
        f.write(f"packets_received: {received}{loss}\n")
        if stats["cal_packets"]:
            f.write(f"calibration_packets_received: {stats['cal_packets']}\n")
        f.write(f"rows_saved: {rows}\n")
        if cal_lines:
            f.write("\n" + "\n".join(cal_lines) + "\n")
        if board_lines:
            f.write("\nboard output:\n")
            f.writelines(f"  {line}\n" for line in board_lines if line.strip())

    for line in cal_lines:
        print(f"[cal] {line}")
    if cal_window and not cal_lines:
        print("[cal] WARNING: no calibration arrived (see the board output)")
    print(f"[saved] {csv_path} -- {rows} rows, {received} packets received{loss}")
    if stats["ignored"]:
        print(f"[note] {stats['ignored']} packets of an unexpected size were ignored "
              f"(is the other application running?)")
    return out_dir, csv_path, rows


def main():
    ap = argparse.ArgumentParser(description="Collect TDC or CT data from the board")
    ap.add_argument("host", help="board address (also used for SSH), e.g. data-yeeter.local")
    ap.add_argument("--app", choices=sorted(APPS), default="tdc",
                    help="which program to start on the board (default: tdc)")
    ap.add_argument("-v", "--threshold", type=int, metavar="MV",
                    help="input threshold in mV, set on the board before the run "
                         "(required; the card powers up at 0 V)")
    ap.add_argument("-n", "--max-events", type=int, default=None)
    ap.add_argument("-t", "--max-seconds", type=float, default=None)
    ap.add_argument("-o", "--outdir", help="run folder (default: data/<date>_<time>_<app>)")
    ap.add_argument("--user", default=SSH_USER,
                    help=f"SSH user on the board (default: {SSH_USER})")
    ap.add_argument("--password", default=SSH_PASS)
    ap.add_argument("--no-ssh", action="store_true",
                    help="only listen; start the program on the board yourself")
    ap.add_argument("--cal-window", type=float, metavar="S",
                    help="TDC: calibrate for S seconds first, from the calibration input")
    ap.add_argument("--cal-every", type=float, metavar="S",
                    help="TDC: calibrate again every S seconds (needs --cal-window)")
    args = ap.parse_args()

    if (args.cal_window or args.cal_every) and args.app != "tdc":
        ap.error("--cal-window and --cal-every are for the TDC only")
    if args.cal_every and not args.cal_window:
        ap.error("--cal-every needs --cal-window")
    if args.cal_every and args.cal_every <= args.cal_window:
        ap.error("--cal-every must be longer than --cal-window")

    if args.threshold is None and not args.no_ssh:
        ap.error("choose an input threshold with -v <mV> (about half the pulse height); "
                 "the card powers up at 0 V and then sees nothing")
    if args.threshold is not None and not 0 <= args.threshold <= 3300:
        ap.error("-v must be 0 to 3300 mV")

    capture(args.host, args.app, args.threshold, args.max_events, args.max_seconds,
            args.outdir, args.user, args.password, args.no_ssh,
            args.cal_window, args.cal_every)
    print("[done]")


if __name__ == "__main__":
    main()
