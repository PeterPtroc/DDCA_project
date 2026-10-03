#!/usr/bin/env python3
"""Convert a little-endian flat RV32 image to readmemh 32-bit words."""

import argparse
from pathlib import Path


def convert(source, destination, limit=65536):
    data = Path(source).read_bytes()
    if len(data) > limit:
        raise ValueError(f"image is {len(data)} bytes; ROM limit is {limit}")
    data += bytes((-len(data)) % 4)
    words = [int.from_bytes(data[i : i + 4], "little") for i in range(0, len(data), 4)]
    Path(destination).write_text(
        "".join(f"{word:08x}\n" for word in words), encoding="ascii"
    )
    return len(words)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--limit", type=int, default=65536)
    args = parser.parse_args()
    words = convert(args.input, args.output, args.limit)
    print(f"HEX PASS: {words} words")


if __name__ == "__main__":
    main()

