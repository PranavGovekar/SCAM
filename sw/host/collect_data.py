#!/usr/bin/env python3
"""
collect_data.py -- SCAM host collector.

Listens on UDP, auto-detects TDC vs CT packet size, saves to CSV.

Usage:
    python collect_data.py -n 18000 192.168.1.100
    python collect_data.py -t 60 -o run1.csv 192.168.1.100
"""

import argparse
import csv
import os
import socket
import struct
import sys
import threading
import time

SSH_USER = "root"
SSH_PASS = "root"
SSH_CTRL_PATH = "/usr/bin/yeet-data-tdc"
UDP_PORT = 8080
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
    rows = []
    for i in range(0, TDC_PACKET_BYTES, 16):
        w0, w1 = struct.unpack_from("<QQ", data, i)
        r_fine   = w0 & 0xFF
        r_coarse = (w0 >> 8) & 0xFFFFFFFFFFFF
        f_fine   = (w0 >> 56) & 0xFF
        f_coarse = w1 & 0xFFFFFFFFFFFF
        ch_id    = (w1 >> 48) & 0xFFFF
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


def trigger_remote(host, password, cmd):
    try:
        import paramiko
    except ImportError:
        print("ERROR: paramiko not installed. pip install -r requirements.txt")
        return
    try:
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(host, username=SSH_USER, password=password)
        print(f"[ssh] {cmd}")
        stdin, stdout, stderr = c.exec_command(cmd, get_pty=True)
        stdin.write(password + "\n")
        stdin.flush()
        for line in stdout:
            print(f"[board] {line.rstrip()}")
        c.close()
    except Exception as e:
        print(f"[ssh error] {e}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("host", help="FPGA IP address (also used for SSH)")
    ap.add_argument("-n", "--max-events", type=int, default=None)
    ap.add_argument("-t", "--max-seconds", type=float, default=None)
    ap.add_argument("-v", "--dac-mv", type=int, default=None,
                    help="DAC threshold in mV (via -v flag on the board)")
    ap.add_argument("-o", "--output", default="capture.csv")
    ap.add_argument("--password", default=SSH_PASS)
    ap.add_argument("--no-ssh", action="store_true")
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
        cmd = f"sudo -S yeet-data-tdc"
        if args.max_events:
            cmd += f" -n {args.max_events}"
        if args.max_seconds:
            cmd += f" -t {int(args.max_seconds)}"
        if args.dac_mv is not None:
            cmd += f" -v {args.dac_mv}"
        cmd += f" {local_ip}"
        trigger_remote(args.host, args.password, cmd)

    listener.join(timeout=5.0)
    print("[done]")


if __name__ == "__main__":
    main()
