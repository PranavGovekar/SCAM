#!/usr/bin/env python3
"""
collect_data.py -- SCAM host collector.

Listens on UDP, auto-detects TDC vs CT packet size, saves to CSV.

Usage:
    python collect_data.py -n 18000 192.168.1.100
    python collect_data.py --app ct -t 60 -o run1.csv 192.168.1.100
"""

import argparse
import csv
import os
import socket
import struct
import sys
import threading
import time

SSH_USER = "petalinux"
SSH_PASS = "petalinux"
APPS = {"tdc": "yeet-data-tdc", "ct": "yeet-data-ct"}
UDP_PORT = 8080
# Time allowed for packets still in flight after the board program exits.
DRAIN_S = 1.0
# A burst of TDC packets easily exceeds the default socket buffer.
RECV_BUFFER_BYTES = 8 * 1024 * 1024
POLL_TIMEOUT_S = 2.0
TDC_PACKET_BYTES = 1440
CT_PACKET_BYTES = 8
HITS_PER_TDC_PACKET = 90


def local_ip_for(host):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((host, 22))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def parse_tdc(data):
    """Decode one TDC packet into (channel, rising coarse, rising fine,
    falling coarse, falling fine) rows.

    Each hit is the 128-bit word that tdc_channel.vhd writes to its FIFO,
    sent least significant byte first:

        [9:0]     rising fine    (delay-line bin, 0..784)
        [57:10]   rising coarse  (400 MHz counter)
        [67:58]   falling fine
        [115:68]  falling coarse
        [127:116] channel id
    """
    rows = []
    for i in range(0, TDC_PACKET_BYTES, 16):
        w0, w1 = struct.unpack_from("<QQ", data, i)
        word = (w1 << 64) | w0
        r_fine   = word & 0x3FF
        r_coarse = (word >> 10) & 0xFFFFFFFFFFFF
        f_fine   = (word >> 58) & 0x3FF
        f_coarse = (word >> 68) & 0xFFFFFFFFFFFF
        ch_id    = (word >> 116) & 0xFFF
        rows.append((ch_id, r_coarse, r_fine, f_coarse, f_fine))
    return rows


def parse_ct(data):
    ev, = struct.unpack("<Q", data)
    ts   = (ev >> 16) & 0xFFFFFFFFFFFF
    co   = ev & 0xFFFF
    def b(n): return (co >> n) & 1
    return [(
        ts, co,
        b(14), b(13), b(12), b(11), b(10),
        b(9), b(8), b(7), b(6), b(5), b(4),
        b(3), b(2), b(1), b(0),
    )]


def listen_and_save(local_ip, out_path, stop_event, max_events):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, RECV_BUFFER_BYTES)
    try:
        sock.bind((local_ip, UDP_PORT))
    except OSError as e:
        print(f"FATAL: cannot bind {local_ip}:{UDP_PORT}: {e}")
        os._exit(1)
    sock.settimeout(POLL_TIMEOUT_S)

    mode = None
    tdc_rows = 0
    ct_rows  = 0

    with open(out_path, "w", newline="") as f:
        w = None

        while not stop_event.is_set():
            try:
                data, _ = sock.recvfrom(2048)
            except socket.timeout:
                continue

            if len(data) == TDC_PACKET_BYTES:
                if mode != "tdc":
                    mode = "tdc"
                    w = csv.writer(f)
                    w.writerow(["Channel_ID", "Rising_Coarse", "Rising_Fine",
                                "Falling_Coarse", "Falling_Fine"])
                    print("[mode] TDC packets detected")
                rows = parse_tdc(data)
                w.writerows(rows)
                tdc_rows += len(rows)
                if max_events and tdc_rows >= max_events:
                    stop_event.set()
                    break

            elif len(data) == CT_PACKET_BYTES:
                if mode != "ct":
                    mode = "ct"
                    w = csv.writer(f)
                    w.writerow(["Timestamp", "Coinc_Out",
                                "ABCD", "BCD", "ACD", "ABD", "ABC",
                                "CD", "BD", "BC", "AD", "AC", "AB",
                                "D", "C", "B", "A"])
                    print("[mode] CT packets detected")
                rows = parse_ct(data)
                w.writerows(rows)
                ct_rows += len(rows)
                if max_events and ct_rows >= max_events:
                    stop_event.set()
                    break

            else:
                # Unknown size, ignore
                pass

    sock.close()
    print(f"[saved] {out_path} -- TDC rows: {tdc_rows}, CT rows: {ct_rows}")


def trigger_remote(host, user, password, cmd):
    try:
        import paramiko
    except ImportError:
        print("ERROR: paramiko not installed. pip install -r requirements.txt")
        return
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
                print(f"[board] {line.rstrip()}")
        except KeyboardInterrupt:
            # Pass the Ctrl+C on to the board program so it stops cleanly, and
            # show the summary it prints on the way out.
            print("[ssh] stopping the board program")
            stdin.write("\x03")
            stdin.flush()
            for line in stdout:
                print(f"[board] {line.rstrip()}")
        c.close()
    except Exception as e:
        print(f"[ssh error] {e}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("host", help="board IP address (also used for SSH)")
    ap.add_argument("--app", choices=sorted(APPS), default="tdc",
                    help="which program to start on the board (default: tdc)")
    ap.add_argument("-n", "--max-events", type=int, default=None)
    ap.add_argument("-t", "--max-seconds", type=float, default=None)
    ap.add_argument("-v", "--dac-mv", type=int, default=None,
                    help="DAC threshold in mV (via -v flag on the board)")
    ap.add_argument("-o", "--output", default="capture.csv")
    ap.add_argument("--user", default=SSH_USER,
                    help=f"SSH user on the board (default: {SSH_USER})")
    ap.add_argument("--password", default=SSH_PASS)
    ap.add_argument("--no-ssh", action="store_true",
                    help="only listen; start the program on the board yourself")
    args = ap.parse_args()

    local_ip = local_ip_for(args.host)
    print(f"Local IP: {local_ip}")
    print(f"Output  : {args.output}")

    stop_event = threading.Event()
    listener = threading.Thread(
        target=listen_and_save,
        args=(local_ip, args.output, stop_event, args.max_events),
        daemon=True,
    )
    listener.start()

    if args.no_ssh:
        # Just listen until max-seconds or Ctrl+C
        try:
            if args.max_seconds:
                time.sleep(args.max_seconds)
                stop_event.set()
            else:
                while listener.is_alive():
                    time.sleep(0.2)
        except KeyboardInterrupt:
            stop_event.set()
    else:
        # -p '' keeps sudo's prompt out of the output; the password is sent on
        # stdin by trigger_remote.
        cmd = f"sudo -S -p '' {APPS[args.app]}"
        if args.max_events:
            cmd += f" -n {args.max_events}"
        if args.max_seconds:
            cmd += f" -t {int(args.max_seconds)}"
        if args.dac_mv is not None:
            cmd += f" -v {args.dac_mv}"
        cmd += f" {local_ip}"
        try:
            trigger_remote(args.host, args.user, args.password, cmd)
            # The board program has exited: let the last packets arrive, then
            # stop the listener so the CSV is closed and complete.
            listener.join(timeout=DRAIN_S)
        except KeyboardInterrupt:
            pass
        stop_event.set()

    # The listener wakes at least every POLL_TIMEOUT_S to see stop_event.
    listener.join(timeout=POLL_TIMEOUT_S + 3.0)
    print("[done]")


if __name__ == "__main__":
    main()
