#!/usr/bin/env python3
"""Single-owner UDP worker used by the rerun-based Streamlit dashboard."""

from __future__ import annotations

import queue
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from m6_stream_client import CompletedFrame, STREAM_GRAYSCALE, STREAM_SOBEL, write_pgm
from m7_activity_monitor import ActivityMonitor, ActivitySample, EventLog
from m7_protocol import M7Status, M7StreamClient


@dataclass(frozen=True)
class WorkerEvent:
    kind: str
    message: str
    created_at: float


class M7StreamWorker:
    """Own exactly one socket/thread and expose bounded frame/status queues."""

    def __init__(self, local_ip: str = "192.168.10.1", fpga_ip: str = "192.168.10.2"):
        self.local_ip = local_ip
        self.fpga_ip = fpga_ip
        self.frames: queue.Queue[CompletedFrame] = queue.Queue(maxsize=2)
        self.events: queue.Queue[WorkerEvent] = queue.Queue(maxsize=200)
        self.activity_samples: queue.Queue[ActivitySample] = queue.Queue(maxsize=50)
        self.status: M7Status | None = None
        self.integrity = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._client: M7StreamClient | None = None
        self._monitor: ActivityMonitor | None = None
        self._event_log: EventLog | None = None
        self._snapshot_dir = Path("docs/m7_captures")

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def _event(self, kind: str, message: str) -> None:
        event = WorkerEvent(kind, message, time.time())
        if self.events.full():
            try:
                self.events.get_nowait()
            except queue.Empty:
                pass
        self.events.put_nowait(event)
        if self._event_log is not None:
            try:
                self._event_log.append_event(kind, message)
            except OSError:
                # Logging must never take down the stream owner.
                pass

    def start(self, stream_id: int, profile: int, threshold: int | None,
              monitor: ActivityMonitor | None = None,
              log_directory: Path = Path("artifacts/m7_runs/dashboard")) -> None:
        if self.running:
            raise RuntimeError("the stream worker is already running")
        if stream_id not in (STREAM_SOBEL, STREAM_GRAYSCALE):
            raise ValueError("invalid stream identifier")
        self._stop.clear()
        self._monitor = monitor
        self._event_log = EventLog(log_directory) if monitor is not None else None
        self._thread = threading.Thread(
            target=self._run,
            args=(stream_id, profile, threshold),
            name="m7-udp-owner",
            daemon=True,
        )
        self._thread.start()

    def stop(self, timeout: float = 3.0) -> None:
        self._stop.set()
        thread = self._thread
        if thread is not None:
            thread.join(timeout)
        if thread is not None and thread.is_alive():
            self._event("error", "worker did not stop within the timeout")
            raise TimeoutError("stream worker is still releasing its UDP socket")
        self._thread = None

    def latest_frame(self) -> CompletedFrame | None:
        latest = None
        while True:
            try:
                latest = self.frames.get_nowait()
            except queue.Empty:
                return latest

    def latest_activity(self) -> ActivitySample | None:
        latest = None
        while True:
            try:
                latest = self.activity_samples.get_nowait()
            except queue.Empty:
                return latest

    def _put_frame(self, frame: CompletedFrame) -> None:
        if self.frames.full():
            try:
                self.frames.get_nowait()
            except queue.Empty:
                pass
        self.frames.put_nowait(frame)

    def _run(self, stream_id: int, profile: int, threshold: int | None) -> None:
        client = M7StreamClient(
            local_ip=self.local_ip, fpga_ip=self.fpga_ip, timeout=0.75
        )
        self._client = client
        try:
            client.open()
            client.configure(profile, threshold)
            self._event("configuration", f"profile={profile} threshold={threshold}")
            # Camera initialization is asynchronous; wait for the status bit before START.
            deadline = time.monotonic() + 3.0
            while time.monotonic() < deadline:
                self.status = client.read_status()
                if self.status.camera_initialized and self.status.core_locked:
                    break
                time.sleep(0.05)
            client.start(stream_id, frame_count=0)
            self._event("session_start", f"stream_id={stream_id}")
            received = 0
            for frame in client.frames(limit=0):
                if self._stop.is_set():
                    break
                received += 1
                self._put_frame(frame)
                if self._monitor is not None:
                    import numpy as np

                    image = np.frombuffer(frame.pixels, dtype=np.uint8).reshape(
                        frame.height, frame.width
                    )
                    sample = self._monitor.process(image, frame.sequence)
                    if self.activity_samples.full():
                        self.activity_samples.get_nowait()
                    self.activity_samples.put_nowait(sample)
                    if sample.transition and self._event_log is not None:
                        self._event_log.append(sample)
                        self._event(sample.transition, f"frame={frame.sequence}")
                        if sample.transition == "activity_begin":
                            path = self._snapshot_dir / f"event_{frame.sequence:08d}.pgm"
                            write_pgm(path, frame)
                if received % 30 == 0:
                    self.status = client.read_status()
                self.integrity = client.counters
        except TimeoutError:
            if not self._stop.is_set():
                self._event("error", "FPGA receive/status timeout")
        except Exception as error:  # surfaced in the dashboard event pane
            self._event("error", str(error))
        finally:
            client.stop()
            client.close()
            self.integrity = client.counters
            self._client = None
            self._event("session_stop", "socket released and STOP sent")
