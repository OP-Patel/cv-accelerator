#!/usr/bin/env python3
"""Bit-exact reference model for the Milestone 2 grayscale Sobel stream."""

from __future__ import annotations

import argparse
import json
import zlib
from pathlib import Path
from typing import Iterable, Sequence


# Converts one RGB565 word with the same expansion and rounded weights as the RTL.
def rgb565_to_gray(pixel: int) -> int:
    red_5 = (pixel >> 11) & 0x1F
    green_6 = (pixel >> 5) & 0x3F
    blue_5 = pixel & 0x1F
    red_8 = (red_5 << 3) | (red_5 >> 2)
    green_8 = (green_6 << 2) | (green_6 >> 4)
    blue_8 = (blue_5 << 3) | (blue_5 >> 2)
    return (77 * red_8 + 150 * green_8 + 29 * blue_8 + 128) >> 8


# Clamps an integer to the unsigned 8-bit pixel range.
def saturate_u8(value: int) -> int:
    return max(0, min(255, value))


# Computes cropped-interior Sobel pixels in deterministic raster order.
def sobel_cropped(image: Sequence[Sequence[int]]) -> list[list[int]]:
    if len(image) < 3 or len(image[0]) < 3:
        return []

    width = len(image[0])
    if any(len(row) != width for row in image):
        raise ValueError("all image rows must have the same width")

    output: list[list[int]] = []
    for center_y in range(1, len(image) - 1):
        output_row: list[int] = []
        for center_x in range(1, width - 1):
            p00, p01, p02 = image[center_y - 1][center_x - 1:center_x + 2]
            p10, _p11, p12 = image[center_y][center_x - 1:center_x + 2]
            p20, p21, p22 = image[center_y + 1][center_x - 1:center_x + 2]
            gx = -p00 + p02 - 2 * p10 + 2 * p12 - p20 + p22
            gy = -p00 - 2 * p01 - p02 + p20 + 2 * p21 + p22
            output_row.append(saturate_u8(abs(gx) + abs(gy)))
        output.append(output_row)
    return output


# Flattens a two-dimensional image in left-to-right, top-to-bottom order.
def raster_bytes(image: Sequence[Sequence[int]]) -> bytes:
    return bytes(pixel for row in image for pixel in row)


# Returns the same finalized CRC-32 produced by stream_checksum.sv.
def stream_crc32(pixels: Iterable[int]) -> int:
    return zlib.crc32(bytes(pixels)) & 0xFFFFFFFF


# Builds the deterministic patterns implemented by synthetic_pixel_source.sv.
def synthetic_image(width: int, height: int, pattern: int) -> list[list[int]]:
    image: list[list[int]] = []
    for y in range(height):
        row: list[int] = []
        for x in range(width):
            if pattern == 0:
                value = 0
            elif pattern == 1:
                value = 255
            elif pattern == 2:
                value = 0 if x < width // 2 else 255
            elif pattern == 3:
                value = 0 if y < height // 2 else 255
            elif pattern == 4:
                value = 255 if ((x >> 3) ^ (y >> 3)) & 1 else 0
            else:
                value = (x * 17 + y * 31 + (x ^ y)) & 0xFF
            row.append(value)
        image.append(row)
    return image


# Runs the command-line checksum report used to derive hardware-demo constants.
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=240)
    parser.add_argument("--patterns", type=int, nargs="*", default=list(range(6)))
    parser.add_argument("--json", type=Path, help="optionally write the report as JSON")
    args = parser.parse_args()

    results = []
    for pattern in args.patterns:
        image = synthetic_image(args.width, args.height, pattern)
        output = sobel_cropped(image)
        crc = stream_crc32(raster_bytes(output))
        result = {
            "pattern": pattern,
            "input_pixels": args.width * args.height,
            "output_pixels": max(0, args.width - 2) * max(0, args.height - 2),
            "crc32": f"{crc:08X}",
        }
        results.append(result)
        print(
            f"PAT={pattern} IN={result['input_pixels']} "
            f"OUT={result['output_pixels']} CRC={result['crc32']}"
        )

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
