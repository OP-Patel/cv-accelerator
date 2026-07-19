#!/usr/bin/env python3
"""Qualify all M7 camera profiles with bounded grayscale and Sobel runs."""

from __future__ import annotations

import argparse
import time

from m6_stream_client import STREAM_GRAYSCALE, STREAM_SOBEL
from m7_protocol import M7StreamClient, PROFILE_NAMES

EXPECTED_READBACK = (0x01041911F1, 0x00041911F1, 0x40041911F1)
MINIMUM_FPS = (7.0, 14.9, 29.0)
MINIMUM_FRAME_PERIOD = (10_000_000, 5_000_000, 2_500_000)
ACTIVE_BYTES = 640 * 240
ACTIVE_LINES = 240
ACTIVE_BYTES_PER_LINE = 640


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=1000)
    parser.add_argument("--local-ip", default="192.168.10.1")
    parser.add_argument("--fpga-ip", default="192.168.10.2")
    parser.add_argument("--timeout", type=float, default=10.0)
    return parser.parse_args()


def wait_for_profile(client: M7StreamClient, profile: int, timeout: float):
    deadline = time.monotonic() + timeout
    last_status = None
    while time.monotonic() < deadline:
        last_status = client.read_status()
        if (last_status.camera_initialized and last_status.timing_readback_valid and
                last_status.active_bytes == ACTIVE_BYTES and
                last_status.active_lines == ACTIVE_LINES and
                last_status.frame_period_cycles >= MINIMUM_FRAME_PERIOD[profile]):
            break
        time.sleep(0.05)
    if last_status is None:
        raise TimeoutError("no M7 status response")
    if not last_status.camera_initialized:
        raise RuntimeError(f"{PROFILE_NAMES[profile]} camera initialization timed out")
    if last_status.profile != profile:
        raise RuntimeError(f"profile mismatch: expected {profile}, got {last_status.profile}")
    if last_status.timing_readback != EXPECTED_READBACK[profile]:
        raise RuntimeError(
            f"{PROFILE_NAMES[profile]} readback mismatch: "
            f"0x{last_status.timing_readback:010x}"
        )
    if (last_status.active_bytes != ACTIVE_BYTES or
            last_status.active_lines != ACTIVE_LINES):
        raise RuntimeError(
            f"{PROFILE_NAMES[profile]} geometry mismatch: "
            f"{last_status.active_bytes} active bytes across "
            f"{last_status.active_lines} lines"
        )
    if last_status.active_bytes // last_status.active_lines != ACTIVE_BYTES_PER_LINE:
        raise RuntimeError(
            f"{PROFILE_NAMES[profile]} line width mismatch: "
            f"{last_status.active_bytes // last_status.active_lines} RGB565 bytes"
        )
    if last_status.frame_period_cycles < MINIMUM_FRAME_PERIOD[profile]:
        raise RuntimeError(
            f"{PROFILE_NAMES[profile]} frame period did not settle: "
            f"{last_status.frame_period_cycles} cycles"
        )
    if last_status.error_flags:
        raise RuntimeError(
            f"{PROFILE_NAMES[profile]} FPGA errors 0x{last_status.error_flags:04x}"
        )
    return last_status


def run_stream(client: M7StreamClient, profile: int, stream_id: int, frames: int):
    client.start(stream_id, frames)
    first = last = None
    received = 0
    try:
        for frame in client.frames(frames):
            received += 1
            first = frame.completed_at if first is None else first
            last = frame.completed_at
    finally:
        client.stop()
    elapsed = 0.0 if first is None or last is None else last - first
    fps = (received - 1) / elapsed if received > 1 and elapsed else 0.0
    status = client.read_status()
    errors = client.counters.total_errors()
    if received != frames:
        raise RuntimeError(f"received {received} of {frames} frames")
    if errors:
        raise RuntimeError(f"host integrity errors: {errors}")
    if status.error_flags:
        raise RuntimeError(f"FPGA errors 0x{status.error_flags:04x}")
    if fps < MINIMUM_FPS[profile]:
        raise RuntimeError(
            f"{PROFILE_NAMES[profile]} cadence {fps:.3f} below "
            f"{MINIMUM_FPS[profile]:.1f} FPS"
        )
    return fps, errors, status.error_flags


def main() -> int:
    args = parse_args()
    if args.frames < 2:
        raise SystemExit("--frames must be at least 2")
    client = M7StreamClient(
        local_ip=args.local_ip, fpga_ip=args.fpga_ip, timeout=args.timeout
    )
    client.open()
    try:
        for profile in range(3):
            client.configure(profile, None)
            status = wait_for_profile(client, profile, args.timeout)
            print(
                f"PROFILE {PROFILE_NAMES[profile]} "
                f"readback=0x{status.timing_readback:010x} "
                f"frame_period={status.frame_period_cycles} "
                f"active_bytes={status.active_bytes} "
                f"active_lines={status.active_lines} "
                f"bytes_per_line={status.active_bytes // status.active_lines} "
                f"errors=0x{status.error_flags:04x}",
                flush=True,
            )
            for stream_id, name in (
                    (STREAM_GRAYSCALE, "grayscale"),
                    (STREAM_SOBEL, "sobel")):
                fps, integrity_errors, fpga_errors = run_stream(
                    client, profile, stream_id, args.frames
                )
                print(
                    f"  {name}: frames={args.frames} fps={fps:.3f} "
                    f"integrity_errors={integrity_errors} "
                    f"fpga_errors=0x{fpga_errors:04x} result=PASS",
                    flush=True,
                )
        client.configure(0, None)
        final_status = wait_for_profile(client, 0, args.timeout)
        print(
            f"PASS: all profiles qualified; returned to safe "
            f"errors=0x{final_status.error_flags:04x}"
        )
    finally:
        client.stop()
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
