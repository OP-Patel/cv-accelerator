#!/usr/bin/env python3
"""Generate readable .mem vectors for small Milestone 2 RTL regressions."""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from golden_sobel import raster_bytes, sobel_cropped, stream_crc32, synthetic_image


# Writes one two-digit hexadecimal pixel per line for SystemVerilog $readmemh.
def write_mem(path: Path, pixels: bytes) -> None:
    path.write_text("".join(f"{pixel:02x}\n" for pixel in pixels), encoding="ascii")


# Produces directed and fixed-seed random cases with expected cropped output.
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("sim/vectors/m2"))
    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--height", type=int, default=16)
    parser.add_argument("--seed", type=int, default=20260712)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    rng = random.Random(args.seed)
    cases = {f"pattern_{index}": synthetic_image(args.width, args.height, index) for index in range(6)}
    cases["single_bright"] = [
        [255 if (x == args.width // 2 and y == args.height // 2) else 0 for x in range(args.width)]
        for y in range(args.height)
    ]
    cases["random"] = [
        [rng.randrange(256) for _x in range(args.width)] for _y in range(args.height)
    ]

    manifest = []
    for name, image in cases.items():
        expected = sobel_cropped(image)
        input_bytes = raster_bytes(image)
        output_bytes = raster_bytes(expected)
        write_mem(args.output / f"{name}_input.mem", input_bytes)
        write_mem(args.output / f"{name}_expected.mem", output_bytes)
        manifest.append(
            {
                "name": name,
                "width": args.width,
                "height": args.height,
                "input_pixels": len(input_bytes),
                "output_pixels": len(output_bytes),
                "crc32": f"{stream_crc32(output_bytes):08X}",
            }
        )

    (args.output / "manifest.json").write_text(
        json.dumps({"seed": args.seed, "cases": manifest}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(cases)} cases to {args.output}")


if __name__ == "__main__":
    main()
