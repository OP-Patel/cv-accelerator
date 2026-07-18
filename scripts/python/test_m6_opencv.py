#!/usr/bin/env python3
"""Prove that the OpenCV baseline is bit-exact with the FPGA golden model."""

from __future__ import annotations

import cv2  # type: ignore
import numpy as np  # type: ignore

from benchmark_m6_opencv import exact_opencv_sobel
from golden_sobel import sobel_cropped, synthetic_image


def main() -> int:
    for pattern in range(6):
        image = synthetic_image(320, 240, pattern)
        expected = np.array(sobel_cropped(image), dtype=np.uint8)
        actual = exact_opencv_sobel(np.array(image, dtype=np.uint8), cv2, np)
        if not np.array_equal(actual, expected):
            differences = int(np.count_nonzero(actual != expected))
            raise SystemExit(
                f"FAIL: OpenCV pattern {pattern} differs at {differences} pixels"
            )
    print("PASS: OpenCV Sobel matches all six 320x240 golden patterns")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
