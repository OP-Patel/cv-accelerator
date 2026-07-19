#!/usr/bin/env python3
"""Run the fair M7 OpenCV/FPGA compute contract and optional live matrix."""

from __future__ import annotations

import argparse
import binascii
import platform
import statistics
import time
from datetime import datetime, timezone
from pathlib import Path

try:
    import psutil
except ImportError:  # setup_check gives the actionable dependency command.
    psutil = None

from m6_stream_client import STREAM_GRAYSCALE, STREAM_SOBEL
from m7_protocol import M7StreamClient, PROFILE_NAMES
from m7_results import SCHEMA_VERSION, write_results

CORE_CLOCK_HZ = 200_000_000
WIDTH, HEIGHT = 320, 240


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true", help="one 300-sample/run smoke benchmark")
    parser.add_argument("--live", action="store_true", help="also run the physical profile/mode matrix")
    parser.add_argument("--local-ip", default="192.168.10.1")
    parser.add_argument("--fpga-ip", default="192.168.10.2")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--threshold", type=int, default=96)
    parser.add_argument("--json-output", type=Path, default=Path("docs/m7_benchmark_results.json"))
    parser.add_argument("--csv-output", type=Path, default=Path("docs/m7_benchmark_results.csv"))
    parser.add_argument("--markdown-output", type=Path,
                        default=Path("docs/milestone7_benchmark_results.md"))
    return parser.parse_args()


def timing_summary(values_ms: list[float]) -> dict[str, float | int]:
    ordered = sorted(values_ms)
    p95 = ordered[max(0, int(len(ordered) * 0.95 + 0.999999) - 1)]
    return {"samples": len(values_ms), "mean_ms": statistics.fmean(values_ms),
            "median_ms": statistics.median(values_ms), "p95_ms": p95,
            "min_ms": min(values_ms), "max_ms": max(values_ms),
            "stdev_ms": statistics.pstdev(values_ms),
            "mean_fps": 1000.0 / statistics.fmean(values_ms)}


def synthetic_input(np):
    y, x = np.indices((HEIGHT, WIDTH), dtype=np.uint16)
    return ((x * 3 + y * 5 + ((x ^ y) & 31)) & 0xFF).astype(np.uint8)


def exact_opencv_sobel(gray, cv2, np):
    gx = cv2.Sobel(gray, cv2.CV_16S, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_16S, 0, 1, ksize=3)
    magnitude = np.abs(gx.astype(np.int32)) + np.abs(gy.astype(np.int32))
    return np.clip(magnitude, 0, 255).astype(np.uint8)[1:-1, 1:-1]


def opencv_runs(samples: int, independent_runs: int, warmup: int, cv2, np):
    gray = synthetic_input(np)
    for _ in range(warmup):
        exact_opencv_sobel(gray, cv2, np)
    output = exact_opencv_sobel(gray, cv2, np)
    expected_crc = binascii.crc32(output.tobytes()) & 0xFFFFFFFF
    runs = []
    for run_index in range(independent_runs):
        timings = []
        for _ in range(samples):
            started = time.perf_counter_ns()
            candidate = exact_opencv_sobel(gray, cv2, np)
            timings.append((time.perf_counter_ns() - started) / 1_000_000.0)
        if not np.array_equal(candidate, output):
            raise RuntimeError("OpenCV-equivalent output changed between runs")
        runs.append({"run": run_index + 1, **timing_summary(timings),
                     "output_crc32": expected_crc})
    return runs, expected_crc


def fpga_runs(client: M7StreamClient, frames: int, independent_runs: int):
    runs = []
    for run_index in range(independent_runs):
        status = client.run_synthetic(frames)
        interval = status.core_frame_interval_cycles
        frame_ms = interval / CORE_CLOCK_HZ * 1000.0
        runs.append({"run": run_index + 1, "frames": frames,
                     "core_clock_hz": CORE_CLOCK_HZ,
                     "frame_interval_cycles": interval,
                     "sustained_frame_ms": frame_ms,
                     "sustained_fps": 1000.0 / frame_ms,
                     "first_input_to_last_output_cycles": status.core_latency_cycles,
                     "accepted_pixels": status.core_input_pixels,
                     "produced_pixels": status.core_output_pixels,
                     "valid_gap_cycles": status.core_valid_gap_cycles,
                     "output_crc32": status.core_output_crc32})
    return runs


def live_session(client: M7StreamClient, profile: int, stream_id: int,
                 threshold: int | None, frames: int) -> dict:
    if psutil is None:
        raise RuntimeError("psutil is required; install scripts/python/requirements-m7.txt")
    client.configure(profile, threshold)
    client.start(stream_id, frames)
    first = last = None
    received = 0
    started = time.perf_counter()
    process = psutil.Process()
    process.cpu_percent(interval=None)
    try:
        for frame in client.frames(frames):
            received += 1
            first = frame.completed_at if first is None else first
            last = frame.completed_at
    finally:
        client.stop()
    elapsed = 0.0 if first is None or last is None else last - first
    return {"profile": PROFILE_NAMES[profile],
            "mode": "grayscale" if stream_id == STREAM_GRAYSCALE else
                    ("threshold" if threshold is not None else "reference_sobel"),
            "frames": received, "request_to_end_seconds": time.perf_counter() - started,
            "request_to_first_frame_seconds": (first - started) if first is not None else 0.0,
            "interframe_fps": (received - 1) / elapsed if received > 1 and elapsed else 0.0,
            "host_cpu_percent": process.cpu_percent(interval=None),
            "integrity_errors": client.counters.total_errors(),
            "integrity": vars(client.counters)}


def main() -> int:
    args = parse_args()
    if not 0 <= args.threshold <= 255:
        raise SystemExit("--threshold must be between 0 and 255")
    try:
        import cv2
        import numpy as np
    except ImportError as error:
        raise SystemExit("Install scripts/python/requirements-m7.txt first") from error
    cv2.setNumThreads(1)
    runs = 1 if args.quick else 5
    samples = 300 if args.quick else 1000
    warmup = 20
    cpu, expected_crc = opencv_runs(samples, runs, warmup, cv2, np)

    client = M7StreamClient(local_ip=args.local_ip, fpga_ip=args.fpga_ip,
                            timeout=args.timeout)
    try:
        client.open()
        hardware = fpga_runs(client, samples, runs)
        live = []
        if args.live:
            live_frames = 300 if args.quick else 1000
            for profile in range(3):
                for stream_id, threshold in ((STREAM_GRAYSCALE, None),
                                             (STREAM_SOBEL, None),
                                             (STREAM_SOBEL, args.threshold)):
                    live.append(live_session(client, profile, stream_id, threshold, live_frames))
    finally:
        client.stop()
        client.close()

    cpu_median = statistics.median(run["median_ms"] for run in cpu)
    fpga_median = statistics.median(run["sustained_frame_ms"] for run in hardware)
    ratio = cpu_median / fpga_median
    crc_match = all(run["output_crc32"] == expected_crc for run in hardware)
    results = {
        "schema_version": SCHEMA_VERSION,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "benchmark_kind": "quick" if args.quick else "full",
        "environment": {"platform": platform.platform(), "processor": platform.processor(),
                        "python": platform.python_version(), "opencv": cv2.__version__,
                        "numpy": np.__version__, "opencv_threads": cv2.getNumThreads(),
                        "cpu_count": psutil.cpu_count(logical=True) if psutil else None},
        "method": {"input": "320x240 deterministic 8-bit coordinate pattern",
                   "output": "318x238 cropped saturating abs(Gx)+abs(Gy)",
                   "warmup": warmup, "samples_per_run": samples,
                   "independent_runs": runs,
                   "separation": "core, CPU kernel, transport, and live FPS are distinct"},
        "opencv_runs": cpu, "fpga_compute_runs": hardware,
        "comparison": {"opencv_median_ms": cpu_median,
                       "fpga_median_frame_ms": fpga_median,
                       "throughput_ratio": ratio, "required_ratio": 1.05,
                       "bit_exact_crc_match": crc_match},
        "live_sessions": live,
    }
    write_results(results, args.json_output, args.csv_output, args.markdown_output)
    print(f"Wrote {args.json_output}, {args.csv_output}, and {args.markdown_output}")
    return 0 if ratio >= 1.05 and crc_match else 1


if __name__ == "__main__":
    raise SystemExit(main())
