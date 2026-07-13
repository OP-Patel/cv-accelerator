#!/usr/bin/env python3
"""Compute expected grayscale and Sobel CRCs for Milestone 3 camera patterns."""

from __future__ import annotations

import argparse
from collections.abc import Callable

from golden_sobel import raster_bytes, rgb565_to_gray, sobel_cropped, stream_crc32


# Returns an RGB565 coordinate pattern matching sim/models/dvp_camera_model.sv.
def coordinate_pixel(x: int, y: int) -> int:
    return ((x & 31) << 11) | ((y & 63) << 5) | ((x + y) & 31)


# Returns a full-range eight-bar RGB565 diagnostic pattern.
def color_bar_pixel(x: int, _y: int, width: int) -> int:
    bars = (0xFFFF, 0xFFE0, 0x07FF, 0x07E0, 0xF81F, 0xF800, 0x001F, 0x0000)
    return bars[min(7, (x * 8) // width)]


# Builds one raster image from a small named RGB565 generator.
def build_rgb_image(width: int, height: int, pattern: str) -> list[list[int]]:
    generators: dict[str, Callable[[int, int], int]] = {
        "black": lambda _x, _y: 0x0000,
        "white": lambda _x, _y: 0xFFFF,
        "coordinate": coordinate_pixel,
        "bars": lambda x, y: color_bar_pixel(x, y, width),
    }
    generator = generators[pattern]
    return [[generator(x, y) for x in range(width)] for y in range(height)]


# Prints the exact count and CRC fields expected from the RTL status line.
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=240)
    parser.add_argument(
        "--pattern", choices=("black", "white", "coordinate", "bars"), default="bars"
    )
    args = parser.parse_args()

    rgb_image = build_rgb_image(args.width, args.height, args.pattern)
    gray_image = [[rgb565_to_gray(pixel) for pixel in row] for row in rgb_image]
    sobel_image = sobel_cropped(gray_image)
    gray_crc = stream_crc32(raster_bytes(gray_image))
    sobel_crc = stream_crc32(raster_bytes(sobel_image))

    print(
        f"PATTERN={args.pattern} LINE={args.height:04X} "
        f"PIX={args.width * args.height:08X} GRAY={gray_crc:08X} "
        f"OUT={(args.width - 2) * (args.height - 2):08X} SOB={sobel_crc:08X}"
    )


if __name__ == "__main__":
    main()
