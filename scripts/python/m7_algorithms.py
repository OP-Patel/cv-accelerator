#!/usr/bin/env python3
"""Bit-exact software models for the M7 FPGA edge modes."""

from __future__ import annotations


def sobel_l1(gray):
    """Return the FPGA-equivalent cropped, saturated abs(Gx)+abs(Gy) image."""
    import numpy as np

    source = np.asarray(gray, dtype=np.int32)
    if source.ndim != 2 or source.shape[0] < 3 or source.shape[1] < 3:
        raise ValueError("gray must be a two-dimensional image at least 3x3")
    p00, p01, p02 = source[:-2, :-2], source[:-2, 1:-1], source[:-2, 2:]
    p10, p12 = source[1:-1, :-2], source[1:-1, 2:]
    p20, p21, p22 = source[2:, :-2], source[2:, 1:-1], source[2:, 2:]
    gx = -p00 + p02 - 2 * p10 + 2 * p12 - p20 + p22
    gy = -p00 - 2 * p01 - p02 + p20 + 2 * p21 + p22
    return np.clip(np.abs(gx) + np.abs(gy), 0, 255).astype(np.uint8)


def threshold_sobel(sobel, threshold: int):
    """Apply the RTL rule: values greater than or equal to threshold become 255."""
    import numpy as np

    if not 0 <= threshold <= 255:
        raise ValueError("threshold must be between 0 and 255")
    source = np.asarray(sobel, dtype=np.uint8)
    return np.where(source >= threshold, 255, 0).astype(np.uint8)


def process_frame(gray, threshold: int | None = None):
    result = sobel_l1(gray)
    return result if threshold is None else threshold_sobel(result, threshold)
