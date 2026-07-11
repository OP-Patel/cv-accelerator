#!/usr/bin/env python3
"""Monitor and optionally record the Milestone 1 USB-UART status stream."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read Arty A7 Milestone 1 status text over 115200 8N1."
    )
    parser.add_argument("--port", help="Serial device, for example COM5 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115_200, help="Baud rate (default: 115200)")
    parser.add_argument("--duration", type=float, default=0.0,
                        help="Stop after this many seconds; zero runs until Ctrl+C")
    parser.add_argument("--output", type=Path,
                        help="Append timestamped received lines to this evidence file")
    parser.add_argument("--list", action="store_true", help="List detected serial ports and exit")
    return parser.parse_args()


def load_pyserial():
    try:
        import serial  # type: ignore
        from serial.tools import list_ports  # type: ignore
    except ImportError as error:
        raise SystemExit(
            "pyserial is required. Install it with: python -m pip install pyserial"
        ) from error
    return serial, list_ports


def main() -> int:
    args = parse_args()
    serial, list_ports = load_pyserial()

    if args.list:
        ports = list(list_ports.comports())
        if not ports:
            print("No serial ports detected.")
        for port in ports:
            print(f"{port.device}: {port.description}")
        return 0

    if not args.port:
        raise SystemExit("--port is required unless --list is used")

    output_file = None
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        output_file = args.output.open("a", encoding="utf-8", newline="")

    start_time = time.monotonic()
    print(f"Monitoring {args.port} at {args.baud} baud, 8 data bits, no parity, 1 stop bit")

    try:
        with serial.Serial(
            port=args.port,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.25,
        ) as connection:
            while args.duration <= 0 or time.monotonic() - start_time < args.duration:
                raw_line = connection.readline()
                if not raw_line:
                    continue

                text = raw_line.decode("ascii", errors="replace").rstrip("\r\n")
                timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
                rendered = f"[{timestamp}] {text}"
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
