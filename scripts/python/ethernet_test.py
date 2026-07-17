#!/usr/bin/env python3
"""Host-side Milestone 4 raw-Ethernet and UDP echo validator.

Raw modes require Scapy plus an Npcap/libpcap-capable interface. UDP mode uses
the operating-system stack after the host adapter is assigned 192.168.10.1/24.
"""
from __future__ import annotations

import argparse
import socket
import struct
import sys
import time
import zlib

FPGA_MAC = "02:00:00:00:00:01"
FPGA_IP = "192.168.10.2"
UDP_PORT = 4000
ETHERTYPE = 0x88B5
MAGIC = b"M4TEST"


def raw_payload(sequence: int) -> bytes:
    pattern = bytes((index ^ (sequence & 0xFF)) for index in range(30))
    body = MAGIC + struct.pack("!IH", sequence, len(pattern)) + pattern
    return body + struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)


def validate_raw(payload: bytes, expected: int | None = None) -> tuple[bool, str, int]:
    if len(payload) < 46 or payload[:6] != MAGIC:
        return False, "bad magic or length", -1
    sequence, pattern_length = struct.unpack("!IH", payload[6:12])
    if pattern_length != 30 or len(payload) != 12 + pattern_length + 4:
        return False, "bad declared payload length", sequence
    expected_pattern = bytes((index ^ (sequence & 0xFF)) for index in range(pattern_length))
    if payload[12:-4] != expected_pattern:
        return False, "payload pattern mismatch", sequence
    received_crc = struct.unpack("<I", payload[-4:])[0]
    if received_crc != (zlib.crc32(payload[:-4]) & 0xFFFFFFFF):
        return False, "payload CRC-32 mismatch", sequence
    if expected is not None and sequence != expected:
        return False, f"sequence gap expected={expected} got={sequence}", sequence
    return True, "ok", sequence


def scapy_import():
    try:
        from scapy.all import Ether, conf, get_if_list, sendp, sniff
    except ImportError as exc:
        raise SystemExit("raw modes require Scapy: python -m pip install scapy") from exc
    return Ether, conf, get_if_list, sendp, sniff


def list_interfaces(_: argparse.Namespace) -> int:
    _, conf, get_if_list, _, _ = scapy_import()
    for name in get_if_list():
        print(f"{name}: {conf.ifaces.dev_from_name(name)}")
    return 0


def raw_send(args: argparse.Namespace) -> int:
    Ether, _, _, sendp, _ = scapy_import()
    frames = [Ether(dst=FPGA_MAC, src=args.source_mac, type=ETHERTYPE) / raw_payload(args.start + n)
              for n in range(args.count)]
    sendp(frames, iface=args.interface, inter=args.interval, verbose=False)
    print(f"PASS raw-send frames={args.count} first={args.start} last={args.start + args.count - 1}")
    return 0


def raw_listen(args: argparse.Namespace) -> int:
    _, _, _, _, sniff = scapy_import()
    valid = bad = gaps = 0
    expected: int | None = None

    def consume(packet):
        nonlocal valid, bad, gaps, expected
        if getattr(packet, "type", None) != ETHERTYPE:
            return
        ok, reason, sequence = validate_raw(bytes(packet.payload), expected)
        if ok:
            valid += 1
            expected = sequence + 1
        else:
            bad += 1
            if reason.startswith("sequence gap"):
                gaps += 1
                expected = sequence + 1
            print(f"FAIL frame={valid + bad} seq={sequence} reason={reason}")

    sniff(iface=args.interface, timeout=args.timeout, count=args.count,
          lfilter=lambda p: getattr(p, "type", None) == ETHERTYPE, prn=consume, store=False)
    passed = valid == args.count and bad == 0 and gaps == 0
    print(f"{'PASS' if passed else 'FAIL'} raw-listen valid={valid} bad={bad} gaps={gaps}")
    return 0 if passed else 1


def udp_echo(args: argparse.Namespace) -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(args.timeout)
    missing = corrupt = reordered = 0
    latencies: list[float] = []
    for sequence in range(args.start, args.start + args.count):
        payload = raw_payload(sequence)
        started = time.perf_counter()
        sock.sendto(payload, (args.fpga_ip, args.port))
        try:
            reply, peer = sock.recvfrom(2048)
        except TimeoutError:
            missing += 1
            continue
        latencies.append(time.perf_counter() - started)
        if peer[0] != args.fpga_ip or reply != payload:
            corrupt += 1
        else:
            ok, _, returned_sequence = validate_raw(reply, sequence)
            if not ok:
                corrupt += 1
            elif returned_sequence != sequence:
                reordered += 1
        if args.interval:
            time.sleep(args.interval)
    sock.close()
    passed = missing == corrupt == reordered == 0
    average_ms = (sum(latencies) / len(latencies) * 1000) if latencies else 0.0
    print(f"{'PASS' if passed else 'FAIL'} udp sent={args.count} received={len(latencies)} "
          f"missing={missing} corrupt={corrupt} reordered={reordered} avg_ms={average_ms:.3f}")
    return 0 if passed else 1


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    interfaces = sub.add_parser("interfaces", help="list Scapy capture interfaces")
    interfaces.set_defaults(func=list_interfaces)
    for name, func in (("raw-send", raw_send), ("raw-listen", raw_listen)):
        item = sub.add_parser(name)
        item.add_argument("--interface", required=True)
        item.add_argument("--count", type=int, default=100)
        item.add_argument("--start", type=int, default=1)
        item.add_argument("--timeout", type=float, default=10.0)
        item.add_argument("--interval", type=float, default=0.01)
        item.add_argument("--source-mac", default="02:00:00:00:00:02")
        item.set_defaults(func=func)
    udp = sub.add_parser("udp", help="run sustained UDP echo validation")
    udp.add_argument("--fpga-ip", default=FPGA_IP)
    udp.add_argument("--port", type=int, default=UDP_PORT)
    udp.add_argument("--count", type=int, default=1000)
    udp.add_argument("--start", type=int, default=1)
    udp.add_argument("--timeout", type=float, default=1.0)
    udp.add_argument("--interval", type=float, default=0.001)
    udp.set_defaults(func=udp_echo)
    return result


def main() -> int:
    args = parser().parse_args()
    if getattr(args, "count", 1) <= 0:
        raise SystemExit("--count must be positive")
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
