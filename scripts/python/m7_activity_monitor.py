#!/usr/bin/env python3
"""Privacy-friendly edge-density/activity scoring and structured event logging."""

from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass(frozen=True)
class Region:
    name: str
    x: int
    y: int
    width: int
    height: int

    def validate(self, frame_width: int, frame_height: int) -> None:
        if not self.name or self.width <= 0 or self.height <= 0:
            raise ValueError("region name and positive dimensions are required")
        if self.x < 0 or self.y < 0:
            raise ValueError("region coordinates cannot be negative")
        if self.x + self.width > frame_width or self.y + self.height > frame_height:
            raise ValueError(f"region {self.name!r} is outside the frame")


@dataclass
class ActivitySettings:
    edge_threshold: int = 96
    trigger_score: float = 0.08
    clear_score: float = 0.03
    hold_frames: int = 8

    def validate(self) -> None:
        if not 0 <= self.edge_threshold <= 255:
            raise ValueError("edge_threshold must be between 0 and 255")
        if not 0.0 <= self.clear_score <= self.trigger_score <= 1.0:
            raise ValueError("scores must satisfy 0 <= clear <= trigger <= 1")
        if self.hold_frames < 0:
            raise ValueError("hold_frames cannot be negative")


@dataclass
class RegionScore:
    name: str
    edge_density: float
    activity_score: float


@dataclass
class ActivitySample:
    sequence: int
    timestamp_utc: str
    active: bool
    transition: str | None
    scores: list[RegionScore]


class ActivityMonitor:
    def __init__(self, regions: list[Region], settings: ActivitySettings | None = None):
        if not regions:
            raise ValueError("at least one region is required")
        self.regions = regions
        self.settings = settings or ActivitySettings()
        self.settings.validate()
        self._previous_masks: dict[str, object] = {}
        self.active = False
        self._hold_remaining = 0

    def process(self, pixels, sequence: int) -> ActivitySample:
        import numpy as np

        image = np.asarray(pixels, dtype=np.uint8)
        if image.ndim != 2:
            raise ValueError("pixels must be a two-dimensional grayscale image")
        frame_height, frame_width = image.shape
        scores: list[RegionScore] = []
        for region in self.regions:
            region.validate(frame_width, frame_height)
            view = image[region.y : region.y + region.height,
                         region.x : region.x + region.width]
            mask = view >= self.settings.edge_threshold
            previous = self._previous_masks.get(region.name)
            activity = 0.0 if previous is None else float(np.count_nonzero(mask != previous)) / mask.size
            density = float(np.count_nonzero(mask)) / mask.size
            self._previous_masks[region.name] = mask.copy()
            scores.append(RegionScore(region.name, density, activity))

        peak = max(score.activity_score for score in scores)
        transition: str | None = None
        if not self.active and peak >= self.settings.trigger_score:
            self.active = True
            self._hold_remaining = self.settings.hold_frames
            transition = "activity_begin"
        elif self.active:
            if peak >= self.settings.clear_score:
                self._hold_remaining = self.settings.hold_frames
            elif self._hold_remaining > 0:
                self._hold_remaining -= 1
            else:
                self.active = False
                transition = "activity_end"

        return ActivitySample(
            sequence=sequence,
            timestamp_utc=datetime.now(timezone.utc).isoformat(),
            active=self.active,
            transition=transition,
            scores=scores,
        )


class EventLog:
    def __init__(self, directory: Path):
        self.directory = directory
        self.directory.mkdir(parents=True, exist_ok=True)
        self.jsonl_path = directory / "activity_events.jsonl"
        self.csv_path = directory / "activity_events.csv"

    def append(self, sample: ActivitySample) -> None:
        record = asdict(sample)
        with self.jsonl_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":")) + "\n")
        new_file = not self.csv_path.exists()
        with self.csv_path.open("a", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            if new_file:
                writer.writerow(("timestamp_utc", "sequence", "active", "transition",
                                 "region", "edge_density", "activity_score"))
            for score in sample.scores:
                writer.writerow((sample.timestamp_utc, sample.sequence, int(sample.active),
                                 sample.transition or "", score.name,
                                 score.edge_density, score.activity_score))

    def append_event(self, kind: str, message: str, **fields: object) -> None:
        """Persist lifecycle and benchmark events beside activity samples."""
        record = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "kind": kind,
            "message": message,
            **fields,
        }
        path = self.directory / "session_events.jsonl"
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":")) + "\n")
