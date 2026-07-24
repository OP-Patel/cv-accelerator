#!/usr/bin/env python3
"""Golden-model checks for reference and thresholded Sobel."""

from __future__ import annotations

import unittest
import binascii

import numpy as np

from benchmark_m7 import (
    EXPECTED_SYNTHETIC_CRC32,
    PROJECTED_FRAME_INTERVAL_CYCLES,
    SYNTHETIC_LANES,
    combined_crc,
    exact_opencv_sobel,
    projected_fpga_runs,
    synthetic_inputs,
)
from m7_algorithms import sobel_l1, threshold_sobel


class M7AlgorithmTests(unittest.TestCase):
    def test_reference_matches_opencv(self) -> None:
        import cv2

        rng = np.random.default_rng(7)
        gray = rng.integers(0, 256, size=(240, 320), dtype=np.uint8)
        gx = cv2.Sobel(gray, cv2.CV_16S, 1, 0, ksize=3)
        gy = cv2.Sobel(gray, cv2.CV_16S, 0, 1, ksize=3)
        expected = np.clip(np.abs(gx.astype(np.int32)) + np.abs(gy.astype(np.int32)),
                           0, 255).astype(np.uint8)[1:-1, 1:-1]
        np.testing.assert_array_equal(sobel_l1(gray), expected)
        np.testing.assert_array_equal(exact_opencv_sobel(gray, cv2, np), expected)

    def test_threshold_is_greater_than_or_equal(self) -> None:
        source = np.array([[0, 95, 96, 255]], dtype=np.uint8)
        expected = np.array([[0, 0, 255, 255]], dtype=np.uint8)
        np.testing.assert_array_equal(threshold_sobel(source, 96), expected)

    def test_shape_and_validation(self) -> None:
        self.assertEqual(sobel_l1(np.zeros((240, 320), dtype=np.uint8)).shape, (238, 318))
        with self.assertRaises(ValueError):
            threshold_sobel(np.zeros((2, 2), dtype=np.uint8), 256)

    def test_parallel_lane_patterns_and_combined_crc(self) -> None:
        import cv2

        inputs = synthetic_inputs(np)
        self.assertEqual(len(inputs), SYNTHETIC_LANES)
        self.assertEqual(len({image.tobytes() for image in inputs}),
                         SYNTHETIC_LANES)
        crcs = [
            binascii.crc32(
                exact_opencv_sobel(image, cv2, np).tobytes()
            ) & 0xFFFFFFFF
            for image in inputs
        ]
        self.assertEqual(crcs[0], 0x5B467F89)
        self.assertEqual(crcs[-1], 0x8F63DE67)
        self.assertEqual(combined_crc(crcs), EXPECTED_SYNTHETIC_CRC32)

    def test_static_projection_is_explicit(self) -> None:
        runs = projected_fpga_runs(1000, 5)
        self.assertEqual(len(runs), 5)
        self.assertEqual(
            runs[0]["frame_interval_cycles"],
            PROJECTED_FRAME_INTERVAL_CYCLES,
        )
        self.assertEqual(runs[0]["measurement"], "routed_rtl_projection")
        self.assertEqual(runs[0]["output_crc32"], EXPECTED_SYNTHETIC_CRC32)
        self.assertEqual(runs[0]["effective_frame_interval_cycles"], 2457.6)


if __name__ == "__main__":
    unittest.main()
