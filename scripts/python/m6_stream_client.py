#!/usr/bin/env python3
"""Reusable M5/M6 UDP session and validated frame reassembly client."""

from __future__ import annotations

import binascii
import socket
import struct
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator


CONTROL_MAGIC = b"M5CT"
VIDEO_MAGIC = b"M5CV"
CONTROL_FORMAT = "!4sBBBBI"
VIDEO_FORMAT = "!4sBBBBIHHIHHHHI"
VIDEO_HEADER_BYTES = struct.calcsize(VIDEO_FORMAT)

STREAM_SOBEL = 0
STREAM_GRAYSCALE = 1
OPCODE_START = 1
OPCODE_STOP = 2


@dataclass
class IntegrityCounters:
    missing_packets: int = 0
    duplicate_packets: int = 0
    reordered_packets: int = 0
    malformed_packets: int = 0
    crc_mismatches: int = 0
    frame_sequence_gaps: int = 0
    discontinuity_frames: int = 0

    def total_errors(self) -> int:
        return (
            self.missing_packets
            + self.duplicate_packets
            + self.reordered_packets
            + self.malformed_packets
            + self.crc_mismatches
            + self.frame_sequence_gaps
        )


@dataclass
class CompletedFrame:
    sequence: int
    stream_id: int
    width: int
    height: int
    pixels: bytes
    packet_count: int
    completed_at: float
    discontinuity: bool


@dataclass
class _FrameAssembly:
    sequence: int
    stream_id: int
    width: int
    height: int
    total_packets: int
    pixels: bytearray
    received: set[int] = field(default_factory=set)
    next_packet: int = 0
    saw_last: bool = False
    discontinuity: bool = False


def control_payload(opcode: int, stream_id: int, frame_count: int) -> bytes:
    return struct.pack(
        CONTROL_FORMAT, CONTROL_MAGIC, 1, opcode, stream_id, 0, frame_count
    )


def write_pgm(path: Path, frame: CompletedFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    header = f"P5\n{frame.width} {frame.height}\n255\n".encode("ascii")
    path.write_bytes(header + frame.pixels)


class M6StreamClient:
    """Own one learned FPGA session and yield complete, validated frames."""

    def __init__(
        self,
        local_ip: str = "192.168.10.1",
        local_port: int = 4001,
        fpga_ip: str = "192.168.10.2",
        timeout: float = 5.0,
    ) -> None:
        self.local_ip = local_ip
        self.local_port = local_port
        self.fpga_endpoint = (fpga_ip, 4001)
        self.timeout = timeout
        self.socket: socket.socket | None = None
        self.counters = IntegrityCounters()
        self._assembly: _FrameAssembly | None = None
        self._last_completed_sequence: int | None = None
        self._stream_id = STREAM_SOBEL

    def open(self) -> None:
        if self.socket is not None:
            return
        stream_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        stream_socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        stream_socket.settimeout(self.timeout)
        try:
            stream_socket.bind((self.local_ip, self.local_port))
        except OSError as error:
            stream_socket.close()
            raise OSError(
                f"cannot bind {self.local_ip}:{self.local_port}; verify that the "
                f"FPGA Ethernet adapter is connected and configured with that IPv4 address "
                f"({error})"
            ) from error
        self.socket = stream_socket

    def close(self) -> None:
        if self.socket is not None:
            self.socket.close()
            self.socket = None

    def __enter__(self) -> "M6StreamClient":
        self.open()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def start(self, stream_id: int, frame_count: int = 0) -> None:
        """Start a session, retrying START so initial ARP resolution cannot lose it."""
        if stream_id not in (STREAM_SOBEL, STREAM_GRAYSCALE):
            raise ValueError("stream_id must be 0 (Sobel) or 1 (grayscale)")
        if frame_count < 0:
            raise ValueError("frame_count must be zero or greater")
        self.open()
        assert self.socket is not None

        request = control_payload(OPCODE_START, stream_id, frame_count)
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            self.socket.sendto(request, self.fpga_endpoint)
            retry_deadline = min(deadline, time.monotonic() + 0.75)
            while time.monotonic() < retry_deadline:
                self.socket.settimeout(max(0.01, retry_deadline - time.monotonic()))
                try:
                    data, _ = self.socket.recvfrom(2048)
                except socket.timeout:
                    break
                if self._is_ack(data, OPCODE_START, stream_id, frame_count):
                    self.socket.settimeout(self.timeout)
                    self._stream_id = stream_id
                    self._assembly = None
                    self._last_completed_sequence = None
                    self.counters = IntegrityCounters()
                    return

        self.socket.settimeout(self.timeout)
        raise TimeoutError("no START acknowledgement from the FPGA")

    def stop(self) -> None:
        if self.socket is None:
            return
        request = control_payload(OPCODE_STOP, self._stream_id, 0)
        try:
            self.socket.sendto(request, self.fpga_endpoint)
        except OSError:
            pass

    def frames(self, limit: int = 0) -> Iterator[CompletedFrame]:
        """Yield frames until limit is reached; zero means continuous streaming."""
        if self.socket is None:
            raise RuntimeError("call start() before receiving frames")

        completed = 0
        while limit == 0 or completed < limit:
            data, _ = self.socket.recvfrom(2048)
            if len(data) == 12 and data[:4] == CONTROL_MAGIC:
                continue
            frame = self._consume_video_datagram(data)
            if frame is not None:
                completed += 1
                yield frame

    @staticmethod
    def _is_ack(data: bytes, opcode: int, stream_id: int, frame_count: int) -> bool:
        if len(data) != 12 or data[:4] != CONTROL_MAGIC:
            return False
        fields = struct.unpack(CONTROL_FORMAT, data)
        magic, version, reply_opcode, reply_stream, flags, reply_count = fields
        return (
            magic == CONTROL_MAGIC
            and version == 1
            and reply_opcode == (opcode | 0x80)
            and reply_stream == stream_id
            and flags == 0
            and reply_count == frame_count
        )

    def _consume_video_datagram(self, data: bytes) -> CompletedFrame | None:
        if len(data) < VIDEO_HEADER_BYTES:
            self.counters.malformed_packets += 1
            return None

        fields = struct.unpack(VIDEO_FORMAT, data[:VIDEO_HEADER_BYTES])
        (
            magic,
            version,
            stream_id,
            flags,
            header_size,
            sequence,
            packet_index,
            total_packets,
            offset,
            payload_length,
            width,
            height,
            reserved,
            expected_crc,
        ) = fields
        payload = data[VIDEO_HEADER_BYTES:]
        expected_dimensions = (318, 238) if stream_id == 0 else (320, 240)
        expected_packets = 74 if stream_id == 0 else 75

        if (
            magic != VIDEO_MAGIC
            or version != 1
            or header_size != VIDEO_HEADER_BYTES
            or reserved != 0
            or stream_id not in (STREAM_SOBEL, STREAM_GRAYSCALE)
            or (width, height) != expected_dimensions
            or total_packets != expected_packets
            or payload_length != len(payload)
            or payload_length == 0
            or payload_length > 1024
            or offset + payload_length > width * height
            or packet_index >= total_packets
            or (flags & 0xF8) != 0
        ):
            self.counters.malformed_packets += 1
            return None

        if (binascii.crc32(payload) & 0xFFFFFFFF) != expected_crc:
            self.counters.crc_mismatches += 1
            return None

        if self._assembly is None or self._assembly.sequence != sequence:
            if self._assembly is not None:
                self.counters.missing_packets += (
                    self._assembly.total_packets - len(self._assembly.received)
                )
            if (
                self._last_completed_sequence is not None
                and sequence > self._last_completed_sequence + 1
            ):
                self.counters.frame_sequence_gaps += (
                    sequence - self._last_completed_sequence - 1
                )
            self._assembly = _FrameAssembly(
                sequence=sequence,
                stream_id=stream_id,
                width=width,
                height=height,
                total_packets=total_packets,
                pixels=bytearray(width * height),
            )

        assembly = self._assembly
        if (assembly.stream_id, assembly.width, assembly.height, assembly.total_packets) != (
            stream_id,
            width,
            height,
            total_packets,
        ):
            self.counters.malformed_packets += 1
            return None
        if packet_index in assembly.received:
            self.counters.duplicate_packets += 1
            return None
        if packet_index != assembly.next_packet:
            self.counters.reordered_packets += 1
        assembly.next_packet = max(assembly.next_packet, packet_index + 1)

        expected_offset = packet_index * 1024
        expected_length = min(1024, width * height - expected_offset)
        expected_flags = (1 if packet_index == 0 else 0) | (
            2 if packet_index == total_packets - 1 else 0
        )
        if (
            offset != expected_offset
            or payload_length != expected_length
            or (flags & 0x03) != expected_flags
        ):
            self.counters.malformed_packets += 1
            return None

        assembly.pixels[offset : offset + payload_length] = payload
        assembly.received.add(packet_index)
        assembly.saw_last |= bool(flags & 0x02)
        assembly.discontinuity |= bool(flags & 0x04)

        if len(assembly.received) != assembly.total_packets or not assembly.saw_last:
            return None

        if assembly.discontinuity:
            self.counters.discontinuity_frames += 1
        completed = CompletedFrame(
            sequence=assembly.sequence,
            stream_id=assembly.stream_id,
            width=assembly.width,
            height=assembly.height,
            pixels=bytes(assembly.pixels),
            packet_count=assembly.total_packets,
            completed_at=time.perf_counter(),
            discontinuity=assembly.discontinuity,
        )
        self._last_completed_sequence = assembly.sequence
        self._assembly = None
        return completed
