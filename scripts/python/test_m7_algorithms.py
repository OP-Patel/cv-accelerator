#!/usr/bin/env python3
"""Golden-model checks for reference and thresholded Sobel."""

from __future__ import annotations

import unittest

import numpy as np

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

    def test_threshold_is_greater_than_or_equal(self) -> None:
        source = np.array([[0, 95, 96, 255]], dtype=np.uint8)
        expected = np.array([[0, 0, 255, 255]], dtype=np.uint8)
        np.testing.assert_array_equal(threshold_sobel(source, 96), expected)

    def test_shape_and_validation(self) -> None:
        self.assertEqual(sobel_l1(np.zeros((240, 320), dtype=np.uint8)).shape, (238, 318))
        with self.assertRaises(ValueError):
            threshold_sobel(np.zeros((2, 2), dtype=np.uint8), 256)


if __name__ == "__main__":
    unittest.main()
