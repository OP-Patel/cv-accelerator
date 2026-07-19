#!/usr/bin/env python3
"""Backward-compatible M7 control/status client built on M6 frame validation."""

from __future__ import annotations

import struct
import time
from dataclasses import dataclass
from typing import Iterator

from m6_stream_client import (
    CONTROL_FORMAT,
    CONTROL_MAGIC,
    CompletedFrame,
    IntegrityCounters,
    M6StreamClient,
    OPCODE_START,
    OPCODE_STOP,
    STREAM_GRAYSCALE,
    STREAM_SOBEL,
)

M7_VERSION = 2
OPCODE_STATUS = 3
OPCODE_CONFIGURE = 4
OPCODE_SYNTHETIC_BENCHMARK = 5
PROFILE_NAMES = ("safe", "medium", "fast")
BUILD_ID = 0x4D370001


def m7_control_payload(opcode: int, stream_id: int, value: int) -> bytes:
    if not 0 <= value <= 0xFFFFFFFF:
        raise ValueError("control value must fit in 32 bits")
    return struct.pack(CONTROL_FORMAT, CONTROL_MAGIC, M7_VERSION,
                       opcode, stream_id, 0, value)


@dataclass(frozen=True)
class M7Status:
    build_id: int
    link_up: bool
    camera_initialized: bool
    core_locked: bool
    timing_readback_valid: bool
    timing_snapshot_valid: bool
    threshold_enabled: bool
    profile: int
    threshold: int
    error_flags: int
    frame_period_cycles: int
    frame_pclk_edges: int
    active_bytes: int
    active_lines: int
    line_pclk_edges: int
    camera_fifo_peak: int
    stream_fifo_peak: int
    core_latency_cycles: int
    core_frame_interval_cycles: int
    core_input_pixels: int
    core_output_pixels: int
    core_valid_gap_cycles: int
    core_completed_frames: int
    timing_readback: int
    synthetic_busy: bool
    synthetic_completed_frames: int
    core_output_crc32: int


class M7StreamClient(M6StreamClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._pending_frames: list[CompletedFrame] = []

    def _exchange(self, opcode: int, stream_id: int, value: int) -> tuple[int, int]:
        self.open()
        assert self.socket is not None
        request = m7_control_payload(opcode, stream_id, value)
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            self.socket.sendto(request, self.fpga_endpoint)
            retry_deadline = min(deadline, time.monotonic() + 0.5)
            while time.monotonic() < retry_deadline:
                self.socket.settimeout(max(0.01, retry_deadline - time.monotonic()))
                try:
                    data, _ = self.socket.recvfrom(2048)
                except TimeoutError:
                    break
                if len(data) == 12 and data[:4] == CONTROL_MAGIC:
                    magic, version, reply_opcode, reply_stream, status, reply_value = struct.unpack(
                        CONTROL_FORMAT, data
                    )
                    if (magic == CONTROL_MAGIC and version == M7_VERSION and
                            reply_opcode == (opcode | 0x80) and reply_stream == stream_id):
                        self.socket.settimeout(self.timeout)
                        return status, reply_value
                else:
                    frame = self._consume_video_datagram(data)
                    if frame is not None:
                        self._pending_frames.append(frame)
        self.socket.settimeout(self.timeout)
        raise TimeoutError(f"no M7 opcode {opcode} acknowledgement from the FPGA")

    def configure(self, profile: int, threshold: int | None) -> None:
        if profile not in range(3):
            raise ValueError("profile must be 0 (safe), 1 (medium), or 2 (fast)")
        if threshold is not None and not 0 <= threshold <= 255:
            raise ValueError("threshold must be between 0 and 255")
        algorithm = 1 if threshold is not None else 0
        value = (profile << 24) | (algorithm << 16) | ((threshold or 0) << 8)
        status, _ = self._exchange(OPCODE_CONFIGURE, STREAM_SOBEL, value)
        if status == 1:
            raise RuntimeError("FPGA rejected configuration while a stream is active")
        if status != 0:
            raise ValueError("FPGA rejected the M7 configuration fields")

    def start(self, stream_id: int, frame_count: int = 0) -> None:
        if stream_id not in (STREAM_SOBEL, STREAM_GRAYSCALE):
            raise ValueError("stream_id must be 0 (Sobel) or 1 (grayscale)")
        if frame_count < 0:
            raise ValueError("frame_count must be zero or greater")
        status, _ = self._exchange(OPCODE_START, stream_id, frame_count)
        if status:
            raise RuntimeError(f"START failed with FPGA status {status}")
        self._stream_id = stream_id
        self._assembly = None
        self._last_completed_sequence = None
        self._pending_frames.clear()
        self.counters = IntegrityCounters()

    def stop(self) -> None:
        if self.socket is None:
            return
        try:
            # Wait for the ACK when possible so a following CONFIGURE cannot
            # race the FPGA's session teardown. Fall back to a best-effort
            # datagram when the link is already unhealthy.
            self._exchange(OPCODE_STOP, self._stream_id, 0)
        except (OSError, TimeoutError):
            try:
                self.socket.sendto(
                    m7_control_payload(OPCODE_STOP, self._stream_id, 0), self.fpga_endpoint
                )
            except OSError:
                pass

    def frames(self, limit: int = 0) -> Iterator[CompletedFrame]:
        if self.socket is None:
            raise RuntimeError("call start() before receiving frames")
        completed = 0
        while limit == 0 or completed < limit:
            if self._pending_frames:
                frame = self._pending_frames.pop(0)
            else:
                data, _ = self.socket.recvfrom(2048)
                if len(data) == 12 and data[:4] == CONTROL_MAGIC:
                    continue
                frame = self._consume_video_datagram(data)
                if frame is None:
                    continue
            completed += 1
            yield frame

    def read_status_page(self, page: int) -> int:
        if not 0 <= page <= 255:
            raise ValueError("status page must fit in one byte")
        status, value = self._exchange(OPCODE_STATUS, STREAM_SOBEL, page)
        if status == 3:
            raise ValueError(f"status page {page} is not implemented")
        if status:
            raise RuntimeError(f"status page {page} failed with FPGA status {status}")
        return value

    def read_status(self) -> M7Status:
        pages = {page: self.read_status_page(page) for page in range(18)}
        flags = pages[1]
        timing_readback = (pages[13] << 8) | (pages[14] & 0xFF)
        return M7Status(
            build_id=pages[0], link_up=bool(flags & (1 << 31)),
            camera_initialized=bool(flags & (1 << 30)),
            core_locked=bool(flags & (1 << 29)),
            timing_readback_valid=bool(flags & (1 << 28)),
            timing_snapshot_valid=bool(flags & (1 << 24)),
            threshold_enabled=bool(flags & (1 << 27)),
            profile=(flags >> 25) & 0x3, threshold=(flags >> 16) & 0xFF,
            error_flags=flags & 0xFFFF, frame_period_cycles=pages[2],
            frame_pclk_edges=pages[3], active_bytes=pages[4],
            active_lines=(pages[5] >> 16) & 0xFFFF,
            line_pclk_edges=pages[5] & 0xFFFF,
            camera_fifo_peak=(pages[6] >> 16) & 0xFFFF,
            stream_fifo_peak=pages[6] & 0xFFFF,
            core_latency_cycles=pages[7], core_frame_interval_cycles=pages[8],
            core_input_pixels=pages[9], core_output_pixels=pages[10],
            core_valid_gap_cycles=pages[11], core_completed_frames=pages[12],
            timing_readback=timing_readback, synthetic_busy=bool(pages[16] >> 31),
            synthetic_completed_frames=pages[16] & 0xFFFF,
            core_output_crc32=pages[17],
        )

    def run_synthetic(self, frames: int, timeout: float = 30.0) -> M7Status:
        if not 1 <= frames <= 0xFFFF:
            raise ValueError("synthetic frame count must be 1..65535")
        status, _ = self._exchange(OPCODE_SYNTHETIC_BENCHMARK, STREAM_SOBEL, frames)
        if status:
            raise RuntimeError(f"synthetic benchmark rejected with status {status}")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            page = self.read_status_page(16)
            busy = bool(page >> 31)
            completed = page & 0xFFFF
            if not busy and completed == frames:
                time.sleep(0.05)  # allow the coherent core-metrics snapshot to refresh
                return self.read_status()
            time.sleep(0.05)
        raise TimeoutError("FPGA synthetic benchmark did not complete")
