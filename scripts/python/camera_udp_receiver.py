#!/usr/bin/env python3
"""Start an M5 session, validate camera datagrams, and write binary PGM frames."""

from __future__ import annotations

import argparse
import binascii
import socket
import struct
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path


CONTROL_MAGIC = b"M5CT"
VIDEO_MAGIC = b"M5CV"
CONTROL_FORMAT = "!4sBBBBI"
VIDEO_FORMAT = "!4sBBBBIHHIHHHHI"
VIDEO_HEADER_BYTES = struct.calcsize(VIDEO_FORMAT)


@dataclass
class IntegrityCounters:
    missing: int = 0
    duplicate: int = 0
    reordered: int = 0
    malformed: int = 0
    crc_mismatch: int = 0

    def total(self) -> int:
        return self.missing + self.duplicate + self.reordered + self.malformed + self.crc_mismatch


@dataclass
class FrameAssembly:
    sequence: int
    stream_id: int
    width: int
    height: int
    total_packets: int
    pixels: bytearray
    received: set[int] = field(default_factory=set)
    next_packet: int = 0
    saw_last: bool = False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-ip", default="192.168.10.1")
    parser.add_argument("--local-port", type=int, default=4001)
    parser.add_argument("--fpga-ip", default="192.168.10.2")
    parser.add_argument("--frames", type=int, default=1, help="zero requests continuous streaming")
    parser.add_argument("--stream", choices=("sobel", "gray"), default="sobel")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--output-dir", type=Path, default=Path("docs/m5_frames"))
    parser.add_argument("--no-stop", action="store_true", help="leave the FPGA session active on exit")
    return parser.parse_args()


def control_payload(opcode: int, stream_id: int, frame_count: int) -> bytes:
    return struct.pack(CONTROL_FORMAT, CONTROL_MAGIC, 1, opcode, stream_id, 0, frame_count)


def wait_for_ack(sock: socket.socket, expected_opcode: int, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        data, _ = sock.recvfrom(2048)
        if len(data) != 12 or data[:4] != CONTROL_MAGIC:
            continue
        magic, version, opcode, stream_id, flags, frame_count = struct.unpack(CONTROL_FORMAT, data)
        if magic == CONTROL_MAGIC and version == 1 and opcode == (expected_opcode | 0x80) and flags == 0:
            print(f"ACK opcode={expected_opcode} stream={stream_id} frames={frame_count}")
            return
    raise TimeoutError(f"no ACK for control opcode {expected_opcode}")


def write_pgm(path: Path, width: int, height: int, pixels: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(f"P5\n{width} {height}\n255\n".encode("ascii") + pixels)


def receive_frames(sock: socket.socket, args: argparse.Namespace) -> tuple[int, IntegrityCounters]:
    counters = IntegrityCounters()
    current: FrameAssembly | None = None
    completed = 0
    requested = args.frames

    while requested == 0 or completed < requested:
        data, _ = sock.recvfrom(2048)
        if len(data) == 12 and data[:4] == CONTROL_MAGIC:
            continue
        if len(data) < VIDEO_HEADER_BYTES:
            counters.malformed += 1
            continue

        fields = struct.unpack(VIDEO_FORMAT, data[:VIDEO_HEADER_BYTES])
        (magic, version, stream_id, flags, header_size, sequence, packet_index,
         total_packets, offset, payload_length, width, height, reserved,
         expected_crc) = fields
        payload = data[VIDEO_HEADER_BYTES:]
        expected_dimensions = (318, 238) if stream_id == 0 else (320, 240)
        expected_packets = 74 if stream_id == 0 else 75

        if (magic != VIDEO_MAGIC or version != 1 or header_size != 32 or reserved != 0 or
                stream_id not in (0, 1) or (width, height) != expected_dimensions or
                total_packets != expected_packets or payload_length != len(payload) or
                payload_length == 0 or payload_length > 1024 or
                offset + payload_length > width * height or
                packet_index >= total_packets):
            counters.malformed += 1
            continue
        if (binascii.crc32(payload) & 0xFFFFFFFF) != expected_crc:
            counters.crc_mismatch += 1
            continue

        if current is None or current.sequence != sequence:
            if current is not None and len(current.received) != current.total_packets:
                counters.missing += current.total_packets - len(current.received)
            current = FrameAssembly(
                sequence=sequence,
                stream_id=stream_id,
                width=width,
                height=height,
                total_packets=total_packets,
                pixels=bytearray(width * height),
            )

        if (current.stream_id, current.width, current.height, current.total_packets) != (
                stream_id, width, height, total_packets):
            counters.malformed += 1
            continue
        if packet_index in current.received:
            counters.duplicate += 1
            continue
        if packet_index != current.next_packet:
            counters.reordered += 1
        current.next_packet = max(current.next_packet, packet_index + 1)

        expected_offset = packet_index * 1024
        expected_length = min(1024, width * height - expected_offset)
        expected_flags = (1 if packet_index == 0 else 0) | (2 if packet_index == total_packets - 1 else 0)
        if offset != expected_offset or payload_length != expected_length or (flags & 0x03) != expected_flags:
            counters.malformed += 1
            continue

        current.pixels[offset:offset + payload_length] = payload
        current.received.add(packet_index)
        current.saw_last |= bool(flags & 0x02)

        if len(current.received) == current.total_packets and current.saw_last:
            output = args.output_dir / f"frame_{sequence:08d}.pgm"
            write_pgm(output, width, height, current.pixels)
            completed += 1
            print(
                f"FRAME sequence={sequence} size={width}x{height} "
                f"packets={total_packets} bytes={len(current.pixels)} file={output}"
            )
            current = None

    return completed, counters


def main() -> int:
    args = parse_args()
    if args.frames < 0:
        raise SystemExit("--frames must be zero or greater")
    stream_id = 0 if args.stream == "sobel" else 1
    endpoint = (args.fpga_ip, 4001)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.settimeout(args.timeout)
    sock.bind((args.local_ip, args.local_port))
    print(f"Bound {args.local_ip}:{args.local_port}; starting {args.stream} stream")

    completed = 0
    counters = IntegrityCounters()
    try:
        sock.sendto(control_payload(1, stream_id, args.frames), endpoint)
        wait_for_ack(sock, 1, args.timeout)
        completed, counters = receive_frames(sock, args)
    except (OSError, TimeoutError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    finally:
        if not args.no_stop:
            try:
                sock.sendto(control_payload(2, stream_id, 0), endpoint)
            except OSError:
                pass
        sock.close()

    print(
        f"SUMMARY frames={completed} missing={counters.missing} "
        f"duplicate={counters.duplicate} reordered={counters.reordered} "
        f"malformed={counters.malformed} crc={counters.crc_mismatch}"
    )
    return 0 if counters.total() == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
