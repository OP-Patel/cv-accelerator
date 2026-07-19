#!/usr/bin/env python3
"""Dependency-free M7 control packing and status decoding checks."""

from __future__ import annotations

import struct
import unittest

from m6_stream_client import CONTROL_FORMAT, STREAM_GRAYSCALE
from m7_protocol import BUILD_ID, M7StreamClient, m7_control_payload


class FakeStatusClient(M7StreamClient):
    def __init__(self):
        super().__init__()
        flags = ((1 << 31) | (1 << 30) | (1 << 29) | (1 << 28) |
                 (1 << 27) | (1 << 25) | (96 << 16) | 0x12)
        self.pages = {page: 0 for page in range(18)}
        self.pages.update({0: BUILD_ID, 1: flags, 2: 13_333_333, 3: 3_200_000,
                           4: 153_600, 5: (240 << 16) | 800,
                           6: (12 << 16) | 25, 7: 76_810, 8: 76_800,
                           9: 76_800, 10: 75_684, 11: 0, 12: 10,
                           13: 0x01041911, 14: 0xF1,
                           16: (1 << 31) | 5, 17: 0x12345678})

    def read_status_page(self, page: int) -> int:
        return self.pages[page]


class EarlyFrameClient(M7StreamClient):
    """Model a complete video frame arriving before the START ACK."""

    def _exchange(self, opcode: int, stream_id: int, value: int) -> tuple[int, int]:
        self._pending_frames.append("early frame")
        return 0, value


class M7ProtocolTests(unittest.TestCase):
    def test_control_payload(self) -> None:
        fields = struct.unpack(CONTROL_FORMAT, m7_control_payload(4, 0, 0x01016000))
        self.assertEqual(fields, (b"M5CT", 2, 4, 0, 0, 0x01016000))

    def test_status_decode(self) -> None:
        status = FakeStatusClient().read_status()
        self.assertEqual(status.build_id, BUILD_ID)
        self.assertTrue(status.link_up and status.core_locked and status.threshold_enabled)
        self.assertEqual(status.profile, 1)
        self.assertEqual(status.threshold, 96)
        self.assertEqual(status.active_lines, 240)
        self.assertEqual(status.core_frame_interval_cycles, 76_800)
        self.assertEqual(status.timing_readback, 0x01041911F1)
        self.assertEqual(status.core_output_crc32, 0x12345678)

    def test_start_preserves_frame_received_before_ack(self) -> None:
        client = EarlyFrameClient()
        client._pending_frames.append("stale frame")
        client.start(STREAM_GRAYSCALE, 1000)
        self.assertEqual(client._pending_frames, ["early frame"])


if __name__ == "__main__":
    unittest.main()
