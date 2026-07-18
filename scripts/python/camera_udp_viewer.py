#!/usr/bin/env python3
"""Display the validated FPGA Sobel or grayscale stream in an OpenCV window."""

from __future__ import annotations

import argparse
import sys
import time
from collections import deque
from pathlib import Path

from m6_stream_client import (
    M6StreamClient,
    STREAM_GRAYSCALE,
    STREAM_SOBEL,
    write_pgm,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-ip", default="192.168.10.1")
    parser.add_argument("--local-port", type=int, default=4001)
    parser.add_argument("--fpga-ip", default="192.168.10.2")
    parser.add_argument("--stream", choices=("sobel", "gray"), default="sobel")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--scale", type=int, default=2, help="integer display scale")
    parser.add_argument("--max-frames", type=int, default=0, help="zero runs until Q/Esc")
    parser.add_argument("--save-dir", type=Path, default=Path("docs/m6_snapshots"))
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


def main() -> int:
    args = parse_args()
    if args.scale < 1:
        raise SystemExit("--scale must be at least 1")
    if args.max_frames < 0:
        raise SystemExit("--max-frames must be zero or greater")

    cv2, np = load_opencv()
    stream_id = STREAM_SOBEL if args.stream == "sobel" else STREAM_GRAYSCALE
    window_name = "Arty A7 FPGA camera stream"
    recent_times: deque[float] = deque()
    completed = 0
    started = time.perf_counter()

    client = M6StreamClient(
        local_ip=args.local_ip,
        local_port=args.local_port,
        fpga_ip=args.fpga_ip,
        timeout=args.timeout,
    )
    try:
        client.open()
        print(
            f"Bound {args.local_ip}:{args.local_port}; requesting continuous "
            f"{args.stream} stream from {args.fpga_ip}"
        )
        client.start(stream_id, frame_count=0)
        started = time.perf_counter()
        print("START acknowledged. Press Q or Esc to stop; press S to save a PGM.")

        for frame in client.frames(limit=args.max_frames):
            now = frame.completed_at
            completed += 1
            recent_times.append(now)
            while recent_times and recent_times[0] < now - 2.0:
                recent_times.popleft()
            display_fps = (
                (len(recent_times) - 1) / (recent_times[-1] - recent_times[0])
                if len(recent_times) > 1
                else 0.0
            )
            total_fps = completed / max(0.001, now - started)

            gray = np.frombuffer(frame.pixels, dtype=np.uint8).reshape(
                frame.height, frame.width
            )
            display = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
            if args.scale != 1:
                display = cv2.resize(
                    display,
                    (frame.width * args.scale, frame.height * args.scale),
                    interpolation=cv2.INTER_NEAREST,
                )

            integrity = client.counters.total_errors()
            mode = "SOBEL FPGA" if frame.stream_id == STREAM_SOBEL else "GRAYSCALE"
            lines = (
                f"{mode}  {frame.width}x{frame.height}",
                f"frame={frame.sequence}  fps={display_fps:.2f}  avg={total_fps:.2f}",
                f"integrity_errors={integrity}  discontinuity={int(frame.discontinuity)}",
            )
            for line_index, text in enumerate(lines):
                y = 22 + line_index * 22
                cv2.putText(
                    display,
                    text,
                    (8, y),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.48,
                    (0, 255, 0) if integrity == 0 else (0, 0, 255),
                    1,
                    cv2.LINE_AA,
                )

            cv2.imshow(window_name, display)
            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                break
            if key == ord("s"):
                output = args.save_dir / f"frame_{frame.sequence:08d}.pgm"
                write_pgm(output, frame)
                print(f"Saved {output}")
            if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
                break

    except (OSError, TimeoutError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("Stopped by user.")
    finally:
        client.stop()
        client.close()
        cv2.destroyAllWindows()

    elapsed = max(0.001, time.perf_counter() - started)
    counters = client.counters
    print(
        f"SUMMARY frames={completed} fps={completed / elapsed:.3f} "
        f"missing={counters.missing_packets} duplicate={counters.duplicate_packets} "
        f"reordered={counters.reordered_packets} malformed={counters.malformed_packets} "
        f"crc={counters.crc_mismatches} frame_gaps={counters.frame_sequence_gaps} "
        f"discontinuity={counters.discontinuity_frames}"
    )
    return 0 if counters.total_errors() == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
