#!/usr/bin/env python3
"""Serial client for the RV32 Real-Time Digital Scope v2.0."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from capture_dump import HEADER, parse_capture_packet, write_csv, write_vcd


def open_serial(port: str, timeout: float):
    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required: python -m pip install pyserial") from exc
    return serial.Serial(port, 115200, timeout=timeout)


def read_exact(link, count: int) -> bytes:
    data = bytearray()
    while len(data) < count:
        chunk = link.read(count - len(data))
        if not chunk:
            raise TimeoutError(f"serial timeout after {len(data)}/{count} bytes")
        data.extend(chunk)
    return bytes(data)


def read_line(link) -> bytes:
    data = link.readline()
    if not data:
        raise TimeoutError("serial timeout waiting for line response")
    return data


def read_measurement(link) -> tuple[int, int, int, int, int]:
    if read_exact(link, 4) != b"MEA2":
        raise RuntimeError("invalid measurement response")
    return struct.unpack("<IIIII", read_exact(link, 20))


def transact(link, args) -> None:
    if args.command == "status":
        link.write(b"s")
        print(read_line(link).decode("ascii", "replace").rstrip())
    elif args.command in {"run", "hold", "single"}:
        link.write({"run": b"r", "hold": b"h", "single": b"1"}[args.command])
        print(f"{args.command} requested")
    elif args.command == "cancel":
        link.write(b"c")
        print(read_line(link).decode("ascii", "replace").rstrip())
    elif args.command == "measure":
        link.write(b"m")
        status, frequency, period, high, low = read_measurement(link)
        duty = 0.0 if period == 0 else 100.0 * high / period
        print(
            f"signal={bool(status & 2)} valid={bool(status & 1)} "
            f"frequency={frequency}Hz period={period} ticks "
            f"high={high} ticks low={low} ticks duty={duty:.2f}%"
        )
    elif args.command == "perf":
        link.write(b"p")
        if read_exact(link, 4) != b"PRF2":
            raise RuntimeError("invalid performance response")
        values = struct.unpack("<9I", read_exact(link, 36))
        names = (
            "cycle", "instret", "stall", "fwd_ex", "fwd_wb",
            "flush", "branch", "taken", "crc",
        )
        print(" ".join(f"{name}={value}" for name, value in zip(names, values)))
    elif args.command == "dump":
        link.write(b"d")
        try:
            magic = read_exact(link, 4)
            if magic == b"ERR2":
                error = read_line(link).decode("ascii", "replace").strip()
                raise RuntimeError(f"capture failed: {error}")
            if magic != b"CAP2":
                raise RuntimeError("invalid capture response")
            prefix = magic + read_exact(link, HEADER.size - 4)
            count = struct.unpack_from("<H", prefix, 6)[0]
            packet = prefix + read_exact(link, (count + 7) // 8 + 2)
        except TimeoutError:
            # The board continues acquiring after a host read times out unless
            # the request is explicitly cancelled.
            link.write(b"c")
            link.flush()
            raise
        header, samples = parse_capture_packet(packet)
        if args.packet:
            args.packet.write_bytes(packet)
        write_csv(samples, args.output)
        if args.vcd:
            write_vcd(samples, args.vcd, header.sample_div)
        print(
            f"dumped {header.sample_count} samples "
            f"({len(packet) - HEADER.size - 2} packed bytes), CRC16 PASS, "
            f"{header.sample_div * 10} ns/step, trigger={header.trigger_edge} "
            f"at {header.trigger_index} -> {args.output}"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="serial port, for example COM9")
    parser.add_argument("--timeout", type=float, default=10.0)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    commands.add_parser("measure")
    commands.add_parser("run")
    commands.add_parser("hold")
    commands.add_parser("single")
    commands.add_parser("cancel")
    commands.add_parser("perf")
    dump = commands.add_parser("dump")
    dump.add_argument("--output", type=Path, default=Path("capture.csv"))
    dump.add_argument("--vcd", type=Path, default=Path("capture.vcd"))
    dump.add_argument("--packet", type=Path, help="optionally preserve the raw CAP2 packet")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    try:
        with open_serial(args.port, args.timeout) as link:
            transact(link, args)
    except (OSError, TimeoutError, RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
