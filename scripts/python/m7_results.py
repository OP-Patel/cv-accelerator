#!/usr/bin/env python3
"""M7 result validation and JSON/CSV/Markdown serialization."""

from __future__ import annotations

import csv
import json
from pathlib import Path

SCHEMA_VERSION = 1


def validate_results(results: dict, require_full: bool = False) -> None:
    required = {"schema_version", "generated_utc", "environment", "method",
                "opencv_runs", "fpga_compute_runs", "comparison"}
    missing = sorted(required - results.keys())
    if missing:
        raise ValueError(f"missing result fields: {', '.join(missing)}")
    if results["schema_version"] != SCHEMA_VERSION:
        raise ValueError("unsupported M7 result schema")
    minimum_runs = 5 if require_full else 1
    if len(results["opencv_runs"]) < minimum_runs or len(results["fpga_compute_runs"]) < minimum_runs:
        raise ValueError(f"at least {minimum_runs} independent compute runs are required")
    comparison = results["comparison"]
    for field in ("opencv_median_ms", "fpga_median_frame_ms", "throughput_ratio",
                  "bit_exact_crc_match"):
        if field not in comparison:
            raise ValueError(f"comparison.{field} is required")


def flatten(prefix: str, value, rows: list[tuple[str, object]]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            flatten(f"{prefix}.{key}" if prefix else str(key), child, rows)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            flatten(f"{prefix}[{index}]", child, rows)
    else:
        rows.append((prefix, value))


def markdown_summary(results: dict) -> str:
    comparison = results["comparison"]
    passed = comparison["throughput_ratio"] >= 1.05 and comparison["bit_exact_crc_match"]
    lines = [
        "# Milestone 7 benchmark result",
        "",
        f"Generated: `{results['generated_utc']}`",
        "",
        "| Measurement | Result |",
        "|---|---:|",
        f"| OpenCV median kernel time | {comparison['opencv_median_ms']:.6f} ms |",
        f"| FPGA median sustained frame time | {comparison['fpga_median_frame_ms']:.6f} ms |",
        f"| FPGA/OpenCV throughput ratio | {comparison['throughput_ratio']:.4f}x |",
        f"| Bit-exact CRC agreement | {comparison['bit_exact_crc_match']} |",
        f"| 5% acceleration contract | {'PASS' if passed else 'FAIL'} |",
        "",
        "Kernel time, core time, transport FPS, and host CPU utilization are separate fields in the JSON/CSV.",
    ]
    if results.get("live_sessions"):
        lines.extend(["", "## Live sessions", "", "| Profile | Mode | Frames | FPS | CPU | Errors |",
                      "|---|---|---:|---:|---:|---:|"])
        for session in results["live_sessions"]:
            lines.append(
                f"| {session['profile']} | {session['mode']} | {session['frames']} | "
                f"{session['interframe_fps']:.4f} | {session.get('host_cpu_percent', 0.0):.1f}% | "
                f"{session['integrity_errors']} |"
            )
    return "\n".join(lines) + "\n"


def write_results(results: dict, json_path: Path, csv_path: Path, markdown_path: Path) -> None:
    validate_results(results, require_full=results.get("benchmark_kind") == "full")
    for path in (json_path, csv_path, markdown_path):
        path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    rows: list[tuple[str, object]] = []
    flatten("", results, rows)
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(("metric", "value"))
        writer.writerows(rows)
    markdown_path.write_text(markdown_summary(results), encoding="utf-8")
