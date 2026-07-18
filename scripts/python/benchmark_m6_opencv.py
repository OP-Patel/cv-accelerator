#!/usr/bin/env python3
"""Benchmark FPGA Sobel streaming against an exact OpenCV CPU Sobel baseline."""

from __future__ import annotations

import argparse
import csv
import json
import math
import platform
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from m6_stream_client import M6StreamClient, STREAM_GRAYSCALE, STREAM_SOBEL


FPGA_CLOCK_HZ = 100_000_000
INPUT_WIDTH = 320
INPUT_HEIGHT = 240


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=300)
    parser.add_argument("--cpu-samples", type=int, default=1000)
    parser.add_argument("--warmup", type=int, default=20)
    parser.add_argument("--local-ip", default="192.168.10.1")
    parser.add_argument("--local-port", type=int, default=4001)
    parser.add_argument("--fpga-ip", default="192.168.10.2")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--cpu-only", action="store_true", help="skip live FPGA sessions")
    parser.add_argument("--opencv-threads", type=int, default=1)
    parser.add_argument(
        "--json-output", type=Path, default=Path("docs/m6_benchmark_results.json")
    )
    parser.add_argument(
        "--csv-output", type=Path, default=Path("docs/m6_benchmark_results.csv")
    )
    return parser.parse_args()


def load_opencv():
    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore
    except ImportError as error:
        raise SystemExit(
            "OpenCV and NumPy are required. Install them with: "
            "py -3 -m pip install -r scripts/python/requirements-m6.txt"
        ) from error
    return cv2, np


def exact_opencv_sobel(gray, cv2, np):
    """Match the FPGA: cropped interior and saturating abs(Gx) + abs(Gy)."""
    gx = cv2.Sobel(gray, cv2.CV_16S, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_16S, 0, 1, ksize=3)
    magnitude = np.abs(gx.astype(np.int32)) + np.abs(gy.astype(np.int32))
    saturated = np.clip(magnitude, 0, 255).astype(np.uint8)
    return saturated[1:-1, 1:-1]


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(len(ordered) * fraction) - 1))
    return ordered[index]


def timing_summary(milliseconds: list[float]) -> dict[str, float]:
    return {
        "samples": float(len(milliseconds)),
        "mean_ms": statistics.fmean(milliseconds),
        "median_ms": statistics.median(milliseconds),
        "p95_ms": percentile(milliseconds, 0.95),
        "min_ms": min(milliseconds),
        "max_ms": max(milliseconds),
        "mean_fps": 1000.0 / statistics.fmean(milliseconds),
    }


def synthetic_cpu_benchmark(frames: int, warmup: int, cv2, np):
    y, x = np.indices((INPUT_HEIGHT, INPUT_WIDTH), dtype=np.uint16)
    gray = ((x * 3 + y * 5 + ((x ^ y) & 31)) & 0xFF).astype(np.uint8)
    for _ in range(warmup):
        exact_opencv_sobel(gray, cv2, np)

    timings: list[float] = []
    output = None
    for _ in range(frames):
        started_ns = time.perf_counter_ns()
        output = exact_opencv_sobel(gray, cv2, np)
        timings.append((time.perf_counter_ns() - started_ns) / 1_000_000.0)
    assert output is not None and output.shape == (238, 318)
    return timing_summary(timings)


def live_stream_benchmark(args: argparse.Namespace, stream_id: int, cv2, np):
    client = M6StreamClient(
        local_ip=args.local_ip,
        local_port=args.local_port,
        fpga_ip=args.fpga_ip,
        timeout=args.timeout,
    )
    kernel_timings: list[float] = []
    first_frame_at: float | None = None
    last_frame_at: float | None = None
    session_started = time.perf_counter()

    try:
        client.open()
        client.start(stream_id, frame_count=args.frames)
        acknowledged_at = time.perf_counter()
        for frame in client.frames(limit=args.frames):
            if first_frame_at is None:
                first_frame_at = frame.completed_at
            last_frame_at = frame.completed_at
            if stream_id == STREAM_GRAYSCALE:
                gray = np.frombuffer(frame.pixels, dtype=np.uint8).reshape(
                    frame.height, frame.width
                )
                started_ns = time.perf_counter_ns()
                output = exact_opencv_sobel(gray, cv2, np)
                kernel_timings.append((time.perf_counter_ns() - started_ns) / 1_000_000.0)
                if output.shape != (238, 318):
                    raise RuntimeError(f"unexpected CPU Sobel shape {output.shape}")
    finally:
        client.stop()
        client.close()

    if first_frame_at is None or last_frame_at is None:
        raise RuntimeError("no complete frames received")

    interframe_seconds = max(0.0, last_frame_at - first_frame_at)
    interframe_fps = (
        (args.frames - 1) / interframe_seconds
        if args.frames > 1 and interframe_seconds > 0
        else 0.0
    )
    result: dict[str, object] = {
        "frames": args.frames,
        "time_to_first_frame_ms": (first_frame_at - acknowledged_at) * 1000.0,
        "session_seconds": last_frame_at - session_started,
        "interframe_fps": interframe_fps,
        "integrity": vars(client.counters),
    }
    if kernel_timings:
        result["opencv_kernel"] = timing_summary(kernel_timings)
    return result


def flatten(prefix: str, value: object, output: dict[str, object]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            flatten(f"{prefix}.{key}" if prefix else str(key), child, output)
    else:
        output[prefix] = value


def write_results(results: dict[str, object], json_path: Path, csv_path: Path) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")

    flattened: dict[str, object] = {}
    flatten("", results, flattened)
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(("metric", "value"))
        for key, value in flattened.items():
            writer.writerow((key, value))


def main() -> int:
    args = parse_args()
    if args.frames < 2:
        raise SystemExit("--frames must be at least 2")
    if args.cpu_samples < 2:
        raise SystemExit("--cpu-samples must be at least 2")
    if args.warmup < 0:
        raise SystemExit("--warmup must be zero or greater")
    if args.opencv_threads < 1:
        raise SystemExit("--opencv-threads must be at least 1")

    cv2, np = load_opencv()
    cv2.setNumThreads(args.opencv_threads)
    synthetic = synthetic_cpu_benchmark(args.cpu_samples, args.warmup, cv2, np)
    fpga_estimated_ms = INPUT_WIDTH * INPUT_HEIGHT / FPGA_CLOCK_HZ * 1000.0

    results: dict[str, object] = {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "benchmark_mode": "cpu_only" if args.cpu_only else "live_fpga_and_cpu",
        "system": {
            "platform": platform.platform(),
            "processor": platform.processor(),
            "python": platform.python_version(),
            "opencv": cv2.__version__,
            "numpy": np.__version__,
            "opencv_threads": cv2.getNumThreads(),
        },
        "method": {
            "input": "320x240 8-bit grayscale",
            "output": "318x238 cropped Sobel",
            "operator": "saturating abs(Gx) + abs(Gy)",
            "note": "FPGA compute time is an RTL-throughput estimate; stream FPS is measured.",
        },
        "cpu_synthetic_kernel": synthetic,
        "fpga_rtl_throughput_estimate": {
            "clock_hz": FPGA_CLOCK_HZ,
            "accepted_pixels_per_clock": 1,
            "frame_compute_ms": fpga_estimated_ms,
            "frame_compute_fps": 1000.0 / fpga_estimated_ms,
            "cpu_time_as_fraction_of_fpga_estimate": synthetic["mean_ms"] / fpga_estimated_ms,
            "cpu_to_fpga_estimated_throughput_ratio": fpga_estimated_ms / synthetic["mean_ms"],
        },
    }

    try:
        if not args.cpu_only:
            print(f"Collecting {args.frames} FPGA Sobel frames...")
            results["fpga_sobel_stream"] = live_stream_benchmark(
                args, STREAM_SOBEL, cv2, np
            )
            print(f"Collecting {args.frames} grayscale frames for the CPU path...")
            results["cpu_live_stream"] = live_stream_benchmark(
                args, STREAM_GRAYSCALE, cv2, np
            )
            fpga_fps = results["fpga_sobel_stream"]["interframe_fps"]  # type: ignore[index]
            cpu_fps = results["cpu_live_stream"]["interframe_fps"]  # type: ignore[index]
            results["end_to_end_fpga_to_cpu_fps_ratio"] = (
                fpga_fps / cpu_fps if cpu_fps else None
            )
    except (OSError, TimeoutError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    write_results(results, args.json_output, args.csv_output)
    print(json.dumps(results, indent=2))
    print(f"Wrote {args.json_output} and {args.csv_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
