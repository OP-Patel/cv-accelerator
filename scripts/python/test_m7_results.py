#!/usr/bin/env python3
"""M7 benchmark schema and three-format writer checks."""

from __future__ import annotations

import unittest
from pathlib import Path

from m7_results import SCHEMA_VERSION, validate_results, write_results


def sample_results() -> dict:
    return {"schema_version": SCHEMA_VERSION, "generated_utc": "2026-07-19T00:00:00Z",
            "benchmark_kind": "quick", "environment": {}, "method": {},
            "opencv_runs": [{"median_ms": 0.5}],
            "fpga_compute_runs": [{"sustained_frame_ms": 0.384}],
            "comparison": {"opencv_median_ms": 0.5,
                           "fpga_median_frame_ms": 0.384,
                           "throughput_ratio": 1.302, "bit_exact_crc_match": True},
            "live_sessions": []}


class M7ResultTests(unittest.TestCase):
    def test_validation_and_outputs(self) -> None:
        results = sample_results()
        validate_results(results)
        root = Path("artifacts/m7_runs/test_scratch/results")
        root.mkdir(parents=True, exist_ok=True)
        write_results(results, root / "result.json", root / "result.csv",
                      root / "result.md")
        self.assertIn("5% acceleration contract | PASS",
                      (root / "result.md").read_text(encoding="utf-8"))
        self.assertTrue((root / "result.json").exists())
        self.assertTrue((root / "result.csv").exists())

    def test_missing_field_rejected(self) -> None:
        results = sample_results(); del results["method"]
        with self.assertRaises(ValueError):
            validate_results(results)


if __name__ == "__main__":
    unittest.main()
