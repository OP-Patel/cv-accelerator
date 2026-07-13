#!/usr/bin/env python3
"""Monitor, validate, and optionally record Milestone 3 UART status lines."""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path


STATUS_PATTERN = re.compile(
    r"^M3 ID=([0-9A-F]{4}) CFG=([PF]) WR=([0-9A-F]{4}) NACK=([0-9A-F]{4}) "
    r"F=([0-9A-F]{8}) LINE=([0-9A-F]{4}) PIX=([0-9A-F]{8}) "
    r"GRAY=([0-9A-F]{8}) OUT=([0-9A-F]{8}) SOB=([0-9A-F]{8}) ERR=([0-9A-F]{4})$"
)


# Defines the serial device and optional evidence-capture controls.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Serial device, for example COM4 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115_200)
    parser.add_argument("--duration", type=float, default=0.0)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--list", action="store_true", help="List serial ports and exit")
    return parser.parse_args()


# Imports pyserial only when live serial access is requested.
def load_pyserial():
    try:
        import serial  # type: ignore
        from serial.tools import list_ports  # type: ignore
    except ImportError as error:
        raise SystemExit(
            "pyserial is required. Install it with: python -m pip install pyserial"
        ) from error
    return serial, list_ports


# Converts one status line to named integers and its pass/fail reason.
def validate_status(text: str) -> tuple[bool, str]:
    match = STATUS_PATTERN.match(text)
    if not match:
        return False, "FORMAT"

    chip_id, config, writes, nacks, frame, lines, pixels, gray, outputs, sobel, errors = (
        match.groups()
    )
    del writes, frame, gray, sobel
    checks = {
        "ID": chip_id == "7670",
        "CFG": config == "P",
        "NACK": int(nacks, 16) == 0,
        "LINE": int(lines, 16) in (0, 240),
        "PIX": int(pixels, 16) in (0, 76_800),
        "OUT": int(outputs, 16) in (0, 75_684),
        "ERR": int(errors, 16) == 0,
    }
    failures = [name for name, passed in checks.items() if not passed]
    return not failures, "PASS" if not failures else ",".join(failures)


# Streams validated lines to the terminal and optional evidence file.
def main() -> int:
    args = parse_args()
    serial, list_ports = load_pyserial()

    if args.list:
        for port in list_ports.comports():
            print(f"{port.device}: {port.description}")
        return 0
    if not args.port:
        raise SystemExit("--port is required unless --list is used")

    output_file = None
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        output_file = args.output.open("a", encoding="utf-8", newline="")

    start_time = time.monotonic()
    try:
        with serial.Serial(args.port, args.baud, timeout=0.25) as connection:
            while args.duration <= 0 or time.monotonic() - start_time < args.duration:
                raw_line = connection.readline()
                if not raw_line:
                    continue
                text = raw_line.decode("ascii", errors="replace").rstrip("\r\n")
                passed, reason = validate_status(text)
                rendered = f"[{'PASS' if passed else 'FAIL'}:{reason}] {text}"
                print(rendered, flush=True)
                if output_file:
                    output_file.write(rendered + "\n")
                    output_file.flush()
    except KeyboardInterrupt:
        print("\nStopped.")
    except serial.SerialException as error:
        print(f"Serial error: {error}", file=sys.stderr)
        return 1
    finally:
        if output_file:
            output_file.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
