#!/usr/bin/env python3
"""Activity state-machine and structured-log tests."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

import numpy as np

from m7_activity_monitor import ActivityMonitor, ActivitySettings, EventLog, Region


class M7ActivityTests(unittest.TestCase):
    def test_begin_hold_end_and_log(self) -> None:
        monitor = ActivityMonitor([Region("roi", 0, 0, 4, 4)],
                                  ActivitySettings(96, 0.25, 0.10, 2))
        idle = np.zeros((4, 4), dtype=np.uint8)
        changed = idle.copy(); changed[:2, :2] = 255
        self.assertIsNone(monitor.process(idle, 0).transition)
        begin = monitor.process(changed, 1)
        self.assertEqual(begin.transition, "activity_begin")
        self.assertTrue(monitor.process(changed, 2).active)
        self.assertTrue(monitor.process(changed, 3).active)
        end = monitor.process(changed, 4)
        self.assertEqual(end.transition, "activity_end")
        scratch = Path("artifacts/m7_runs/test_scratch/activity")
        scratch.mkdir(parents=True, exist_ok=True)
        log = EventLog(scratch)
        log.jsonl_path.unlink(missing_ok=True)
        log.csv_path.unlink(missing_ok=True)
        log.append(begin)
        record = json.loads(log.jsonl_path.read_text(encoding="utf-8"))
        self.assertEqual(record["transition"], "activity_begin")
        self.assertTrue(log.csv_path.exists())
        log.append_event("session_start", "test", profile="safe")
        events = (scratch / "session_events.jsonl").read_text(encoding="utf-8").splitlines()
        self.assertEqual(json.loads(events[-1])["kind"], "session_start")


if __name__ == "__main__":
    unittest.main()
