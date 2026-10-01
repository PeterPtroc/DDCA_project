#!/usr/bin/env python3
"""Serial command-line client for the RV32 Digital Analyzer."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from capture_dump import write_csv, write_vcd

RATE_CODES = {
    "100m": b"1",
    "50m": b"5",
    "25m": b"6",
    "10m": b"2",
    "1m": b"3",
    "100k": b"4",
}


def open_serial(port: str, timeout: float):
    try:
        import serial
    except ImportError as exc:
        raise SystemExit(
            "pyserial is required: python -m pip install pyserial"
        ) from exc
    return serial.Serial(port, 115200, timeout=timeout)


def read_exact(link, count: int) -> bytes:
    data = bytearray()
    while len(data) < count:
        chunk = link.read(count - len(data))
        if not chunk:
            raise TimeoutError(f"serial timeout after {len(data)}/{count} bytes")
        data.extend(chunk)
    return bytes(data)


def transact(link, args) -> None:
    if args.command == "status":
        link.write(b"s")
        print(link.readline().decode("ascii", "replace").rstrip())
    elif args.command == "arm":
        link.write(b"a")
        print("capture armed")
    elif args.command == "rate":
        link.write(RATE_CODES[args.rate])
        print(f"sample rate set to {args.rate}")
    elif args.command == "channel":
        link.write(bytes((ord("c"), ord("0") + args.channel)))
        print(f"trigger channel set to {args.channel}")
    elif args.command == "edge":
        link.write(b"r" if args.edge == "rising" else b"f")
        print(f"trigger edge set to {args.edge}")
    elif args.command == "measure":
        link.write(b"m")
        if read_exact(link, 4) != b"MEA0":
            raise RuntimeError("invalid measurement response")
        frequency, period, high = struct.unpack("<III", read_exact(link, 12))
        duty = 0.0 if period == 0 else (100.0 * high / period)
        print(
            f"frequency={frequency}Hz period={period} ticks high={high} ticks duty={duty:.1f}%"
        )
    elif args.command == "dump":
        link.write(b"d")
        if read_exact(link, 4) != b"CAP0":
            raise RuntimeError("invalid capture response")
        count = struct.unpack("<H", read_exact(link, 2))[0]
        samples = list(read_exact(link, count))
        write_csv(samples, args.output)
        if args.vcd:
            write_vcd(samples, args.vcd, args.sample_rate)
        print(f"dumped {count} samples to {args.output}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="serial port, for example COM9")
    parser.add_argument("--timeout", type=float, default=2.0)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    commands.add_parser("arm")
    rate = commands.add_parser("rate")
    rate.add_argument("rate", choices=RATE_CODES)
    channel = commands.add_parser("channel")
    channel.add_argument("channel", type=int, choices=range(8))
    edge = commands.add_parser("edge")
    edge.add_argument("edge", choices=("rising", "falling"))
    commands.add_parser("measure")
    dump = commands.add_parser("dump")
    dump.add_argument("--output", type=Path, default=Path("capture.csv"))
    dump.add_argument("--vcd", type=Path, default=Path("capture.vcd"))
    dump.add_argument("--sample-rate", type=int, default=100_000_000)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    try:
        with open_serial(args.port, args.timeout) as link:
            transact(link, args)
    except (OSError, TimeoutError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
