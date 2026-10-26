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
    python collect_data.py -v 0:120,1:150 -t 60 data-yeeter.local   # a threshold per channel
    python collect_data.py -v 39 -t 600 -o data/pedestal_39mV data-yeeter.local   # name the run

The input threshold (-v, millivolts) is required: the FMC DIO card powers up
with its threshold at 0 V and then sees no pulses. -v 250 sets every channel;
-v 0:120,1:150 sets only the card channels named (0 to 3 = TDC channels 0 to
3, 4 = the calibration input) and leaves the others as they are.

Only packets from the board are recorded, and only words with a TDC channel
ID count as hits; anything else is reported in run.txt. A run does not start
while another board program is running.

A run folder (data/<date>_<time>_<app>/ by default) holds:
    hits.csv   one row per TDC hit or CT event
    run.txt    settings, the board program's output and packet counts, and
               run_seconds: how long the board took data (for rates)
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
# A burst of TDC packets easily exceeds the default socket buffer. The kernel
# gives at most net.core.rmem_max (raise it to 64 MB on a Raspberry Pi with
# sysctl, or packets are lost at high rates).
RECV_BUFFER_BYTES = 64 * 1024 * 1024
POLL_TIMEOUT_S = 2.0
# Threshold DAC channel of each FMC DIO card channel (schematic EDA-02408):
# card channel 3 is DAC channel 7; DAC channels 3 and 6 are not connected.
CARD_TO_DAC = {0: 0, 1: 1, 2: 2, 3: 7, 4: 4}
PACKET_BYTES = {"tdc": 1440, "ct": 8}
EVENTS_PER_PACKET = {"tdc": 90, "ct": 1}
# Packets decoded per step when the raw capture is converted to CSV.
DECODE_CHUNK_PACKETS = 20000

DATA_DIR = Path(__file__).resolve().parents[2] / "data"

TDC_COLUMNS = ["Channel_ID", "Rising_Coarse", "Rising_Fine", "Falling_Coarse", "Falling_Fine"]
CT_COLUMNS = ["Timestamp", "Coinc_Out", "ABCD", "BCD", "ACD", "ABD", "ABC",
              "CD", "BD", "BC", "AD", "AC", "AB", "D", "C", "B", "A"]

_MASK48 = np.uint64((1 << 48) - 1)

# Channel IDs (bits 127:116) of TDC hits; any other word is not a hit.
TDC_CHANNELS = 4
# TDC calibration words (yeet-data-tdc.c), bits 127:120 of a word with bit 127 set.
WORD_CAL_HEADER = 0xC1
WORD_CAL_TABLE = 0xC2
WORD_PADDING = 0xCF
CLOCK_PERIOD_PS = 2500.0
TABLE_UNIT_PS = 1 / 16
TABLE_PER_WORD = 6
LINE_NAMES = ["ch0_start", "ch0_stop", "ch1_start", "ch1_stop",
              "ch2_start", "ch2_stop", "ch3_start", "ch3_stop"]
CAL_FLAGS = {0x001: "few hits", 0x002: "empty codes", 0x004: "wide bins",
             0x008: "code range", 0x010: "calibration hits dropped"}


def tdc_words(buf):
    """The 128-bit words of TDC packets as (low, high) 64-bit halves, a mask
    of the physics hits (channel ID 0 .. TDC_CHANNELS-1) and a mask of the
    words that are neither hits nor calibration or padding words."""
    w = np.frombuffer(buf, dtype="<u8").reshape(-1, 2)
    physics = (w[:, 1] >> np.uint64(52)) < TDC_CHANNELS
    kind = w[:, 1] >> np.uint64(56)
    board = (kind == WORD_CAL_HEADER) | (kind == WORD_CAL_TABLE) | (kind == WORD_PADDING)
    return w, physics, ~physics & ~board


def parse_tdc(buf):
    """Decode TDC packets into rows of (channel, rising coarse, rising fine,
    falling coarse, falling fine). Every word that is not a hit (calibration,
    padding, or an unknown channel ID) is skipped.

    Each hit is the 128-bit word that tdc_channel.vhd writes to its FIFO,
    sent least significant byte first:

        [9:0]     rising fine    (delay-line bin, 0..784)
        [57:10]   rising coarse  (400 MHz counter)
        [67:58]   falling fine
        [115:68]  falling coarse
        [127:116] channel id (bit 127 set: not a hit, see decode_calibrations)
    """
    w, physics, _ = tdc_words(buf)
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
    """This computer's address towards the board, and the board's address."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((host, 22))
        return s.getsockname()[0], s.getpeername()[0]
    except OSError as e:
        sys.exit(f"ERROR: no network route to {host} ({e}). "
                 "Check the cable and the board address.")
    finally:
        s.close()


def listen(local_ip, board_ip, raw_path, app, stop_event, max_events, stats):
    """Write every packet of the expected size from board_ip to raw_path,
    unchanged. Decoding waits until the run is over so that no time is lost
    here."""
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
                data, (sender, _) = sock.recvfrom(2048)
            except socket.timeout:
                continue
            if sender != board_ip:
                stats["foreign"] += 1
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
    count, the TDC calibration words as (low, high, rows before it), and the
    number of TDC words that were neither (left out of the CSV)."""
    size = PACKET_BYTES[app]
    parse = parse_tdc if app == "tdc" else parse_ct
    rows_written = 0
    cal_words = []
    unknown_words = 0
    with open(raw_path, "rb") as src, open(csv_path, "w") as dst:
        dst.write(",".join(TDC_COLUMNS if app == "tdc" else CT_COLUMNS) + "\n")
        while True:
            buf = src.read(size * DECODE_CHUNK_PACKETS)
            if not buf:
                break
            if app == "tdc":
                w, physics, unknown = tdc_words(buf)
                unknown_words += int(np.count_nonzero(unknown))
                idx = np.nonzero(~physics & ~unknown)[0]
                before = rows_written + np.cumsum(physics)[idx]
                cal_words += [(int(w[i, 0]), int(w[i, 1]), int(b)) for i, b in zip(idx, before)]
            rows = parse(buf)
            if max_events:
                rows = rows[:max_events - rows_written]
            np.savetxt(dst, rows, fmt="%d", delimiter=",")
            rows_written += len(rows)
            if max_events and rows_written >= max_events:
                break
    return rows_written, cal_words, unknown_words


def save_calibrations(out_dir, cal_words):
    """Write calibrations/cal_<n>.json. Returns summary lines for run.txt and
    the number of calibrations."""
    cals = decode_calibrations(cal_words)
    if not cals:
        return [], 0
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
    return lines, len(cals)


def trigger_remote(host, user, password, cmd):
    """Run cmd on the board and show its output. Returns the output lines and
    the seconds from the board's "=== ... STREAM ===" line to its "=== DONE ==="
    line, which is how long it took data (None if either line is missing)."""
    lines = []
    marks = {}
    try:
        import paramiko
    except ImportError:
        print("ERROR: paramiko not installed. pip install -r requirements.txt")
        return lines, None

    def show(line):
        line = line.rstrip()
        if line.strip() == password:      # the terminal echoes the sudo password
            return
        if line.endswith("STREAM ==="):
            marks["start"] = time.time()
        elif line == "=== DONE ===":
            marks["end"] = time.time()
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
    if "start" in marks and "end" in marks:
        return lines, marks["end"] - marks["start"]
    return lines, None


def board_shell(host, user, password, cmd, timeout=30):
    """Run a short command on the board and return its output."""
    import paramiko
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, password=password, timeout=15)
    try:
        _, stdout, _ = c.exec_command(cmd, timeout=timeout)
        return stdout.read().decode()
    finally:
        c.close()


# Prints the name of each board program that is running (no pgrep needed).
BOARD_PROGRAMS_RUNNING = ("cat /proc/[0-9]*/comm 2>/dev/null | grep -x "
                          + " ".join(f"-e {p}" for p in APPS.values()))

# PL die temperature of the ZCU102 (AMS), in millidegrees C.
PL_TEMP_READ = ("for d in /sys/bus/iio/devices/iio:device*; do "
                "[ \"$(cat $d/name)\" = xilinx-ams ] && cat $d/in_temp20_input; done")


def read_die_temp(host, user=SSH_USER, password=SSH_PASS):
    """PL die temperature in C, or None if it could not be read."""
    try:
        return float(board_shell(host, user, password, PL_TEMP_READ).split()[0]) / 1000
    except Exception:
        return None


def parse_thresholds(text):
    """'250' -> 250 (every channel); '0:120,1:150' -> {0: 120, 1: 150}, keyed
    by card channel. Raises ValueError on anything else."""
    if ":" not in text:
        mv = int(text)
        if not 0 <= mv <= 3300:
            raise ValueError("thresholds are 0 to 3300 mV")
        return mv
    out = {}
    for item in text.split(","):
        ch, mv = (int(x) for x in item.split(":"))
        if ch not in CARD_TO_DAC or not 0 <= mv <= 3300:
            raise ValueError("card channels are 0 to 4, thresholds 0 to 3300 mV")
        out[ch] = mv
    return out


def format_thresholds(t):
    if t is None:
        return "not set"
    if isinstance(t, dict):
        return ",".join(f"{ch}:{mv}" for ch, mv in sorted(t.items()))
    return str(t)


def set_channel_thresholds(host, user, password, thresholds):
    """Set the card channels in {channel: mV} with the board's threshold program."""
    cmd = " && ".join(f"echo '{password}' | sudo -S -p '' threshold -c {CARD_TO_DAC[ch]} {mv}"
                      for ch, mv in sorted(thresholds.items()))
    for line in board_shell(host, user, password, cmd + " 2>&1").splitlines():
        if line.strip():
            print(f"[board] {line.strip()}")


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
    threshold_mv: mV for every channel, or {channel: mV} for some channels.
    cal_window/cal_every (seconds, TDC): calibrate first, and repeat."""
    if not no_ssh:
        # Another capture would share the TDC, the DMA and the thresholds.
        running = board_shell(host, user, password, BOARD_PROGRAMS_RUNNING).split()
        if running:
            sys.exit(f"ERROR: {', '.join(sorted(set(running)))} is already running on the "
                     "board (another capture?). Not starting; wait for it to end.")
    out_dir = Path(out_dir) if out_dir else new_run_dir(app)
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "hits.csv"
    raw_path = out_dir / "hits.raw"

    local_ip, board_ip = local_ip_for(host)
    print(f"Local IP : {local_ip}")
    print(f"Run      : {out_dir}")

    temp_start = None if no_ssh else read_die_temp(host, user, password)
    if isinstance(threshold_mv, dict):
        if no_ssh:
            sys.exit("ERROR: per-channel thresholds need the SSH login (not --no-ssh)")
        set_channel_thresholds(host, user, password, threshold_mv)

    stop_event = threading.Event()
    stats = {"packets": 0, "cal_packets": 0, "ignored": 0, "foreign": 0}
    listener = threading.Thread(
        target=listen, args=(local_ip, board_ip, raw_path, app, stop_event, max_events, stats),
        daemon=True)
    listener.start()
    started = datetime.now()

    board_lines = []
    cmd = None
    stream_s = None
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
        if threshold_mv is not None and not isinstance(threshold_mv, dict):
            cmd += f" -v {threshold_mv}"
        if cal_window:
            cmd += f" -c {cal_window:g}"
        if cal_every:
            cmd += f" -C {cal_every:g}"
        cmd += f" {local_ip}"
        try:
            board_lines, stream_s = trigger_remote(host, user, password, cmd)
            # The board program has exited: let the last packets arrive.
            listener.join(timeout=DRAIN_S)
        except KeyboardInterrupt:
            pass
        stop_event.set()

    # The listener wakes at least every POLL_TIMEOUT_S to see stop_event.
    listener.join(timeout=POLL_TIMEOUT_S + 3.0)

    temp_end = None if no_ssh else read_die_temp(host, user, password)
    print("[data] decoding")
    rows, cal_words, unknown_words = raw_to_csv(raw_path, csv_path, app, max_events)
    raw_path.unlink()
    cal_lines, n_cals = save_calibrations(out_dir, cal_words)
    # Time the board recorded hits: the stream minus its calibration windows.
    run_s = stream_s - n_cals * (cal_window or 0) if stream_s else None

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
        f.write(f"threshold_mv: {format_thresholds(threshold_mv)}\n")
        for name, t in (("die_temp_start_c", temp_start), ("die_temp_end_c", temp_end)):
            f.write(f"{name}: {'not read' if t is None else f'{t:.2f}'}\n")
        f.write(f"max_events: {max_events or 'none'}\n")
        f.write(f"max_seconds: {max_seconds or 'none'}\n")
        f.write(f"run_seconds: {'not measured' if run_s is None else f'{run_s:.2f}'}\n")
        if cmd:
            f.write(f"board_command: {cmd}\n")
        if cal_window:
            f.write(f"calibration: {cal_window:g} s window"
                    + (f", every {cal_every:g} s" if cal_every else ", once") + "\n")
        f.write(f"packets_received: {received}{loss}\n")
        if stats["cal_packets"]:
            f.write(f"calibration_packets_received: {stats['cal_packets']}\n")
        f.write(f"rows_saved: {rows}\n")
        if unknown_words:
            f.write(f"unknown_words_dropped: {unknown_words}\n")
        if stats["foreign"]:
            f.write(f"packets_from_other_senders_ignored: {stats['foreign']}\n")
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
    if stats["foreign"]:
        print(f"[note] {stats['foreign']} packets from another sender than {board_ip} were ignored")
    if unknown_words:
        print(f"[WARNING] {unknown_words} words were neither hits nor calibration words; "
              f"left out of hits.csv")
    return out_dir, csv_path, rows


def main():
    ap = argparse.ArgumentParser(description="Collect TDC or CT data from the board")
    ap.add_argument("host", help="board address (also used for SSH), e.g. data-yeeter.local")
    ap.add_argument("--app", choices=sorted(APPS), default="tdc",
                    help="which program to start on the board (default: tdc)")
    ap.add_argument("-v", "--threshold", metavar="MV",
                    help="input threshold in mV for every channel, or per channel as "
                         "CH:MV,CH:MV (required; the card powers up at 0 V)")
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
    if args.threshold is not None:
        try:
            args.threshold = parse_thresholds(args.threshold)
        except ValueError as e:
            ap.error(f"-v {args.threshold}: {e}")

    capture(args.host, args.app, args.threshold, args.max_events, args.max_seconds,
            args.outdir, args.user, args.password, args.no_ssh,
            args.cal_window, args.cal_every)
    print("[done]")


if __name__ == "__main__":
    main()
