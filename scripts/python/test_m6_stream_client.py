#!/usr/bin/env python3
"""Dependency-free checks for M6 UDP header validation and frame reassembly."""

from __future__ import annotations

import binascii
import struct
import unittest

from m6_stream_client import M6StreamClient, VIDEO_FORMAT


class M6StreamClientTests(unittest.TestCase):
    @staticmethod
    def datagram(sequence: int, packet_index: int, payload: bytes) -> bytes:
        total_packets = 74
        flags = (1 if packet_index == 0 else 0) | (
            2 if packet_index == total_packets - 1 else 0
        )
        header = struct.pack(
            VIDEO_FORMAT,
            b"M5CV",
            1,
            0,
            flags,
            32,
            sequence,
            packet_index,
            total_packets,
            packet_index * 1024,
            len(payload),
            318,
            238,
            0,
            binascii.crc32(payload) & 0xFFFFFFFF,
        )
        return header + payload

    def test_complete_sobel_frame(self) -> None:
        client = M6StreamClient()
        pixels = bytes(index & 0xFF for index in range(318 * 238))
        completed = None
        for packet_index in range(74):
            offset = packet_index * 1024
            payload = pixels[offset : offset + 1024]
            completed = client._consume_video_datagram(
                self.datagram(7, packet_index, payload)
            )
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.sequence, 7)
        self.assertEqual(completed.pixels, pixels)
        self.assertEqual(completed.packet_count, 74)
        self.assertEqual(client.counters.total_errors(), 0)

    def test_crc_corruption_is_counted(self) -> None:
        client = M6StreamClient()
        packet = bytearray(self.datagram(0, 0, bytes(1024)))
        packet[-1] ^= 1
        self.assertIsNone(client._consume_video_datagram(bytes(packet)))
        self.assertEqual(client.counters.crc_mismatches, 1)


if __name__ == "__main__":
    unittest.main()
