#!/usr/bin/env python3
"""Compare reference and RTL architectural retire traces."""

import argparse
import csv
import sys
from pathlib import Path

from rv32_ref import TRACE_FIELDS

HEX_FIELDS = {"pc", "insn", "rd_data", "mem_addr", "mem_data"}


def read_trace(path):
    rows = []
    with Path(path).open(newline="", encoding="ascii") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != TRACE_FIELDS:
            raise ValueError(f"{path}: unexpected trace header {reader.fieldnames}")
        for line_number, raw in enumerate(reader, 2):
            try:
                rows.append(
                    {
                        field: int(raw[field], 16 if field in HEX_FIELDS else 10)
                        for field in TRACE_FIELDS
                    }
                )
            except (KeyError, ValueError) as error:
                raise ValueError(
                    f"{path}:{line_number}: invalid trace row: {error}"
                ) from error
    return rows


def compare_traces(reference, rtl):
    common = min(len(reference), len(rtl))
    for index in range(common):
        expected = reference[index]
        actual = rtl[index]
        for field in TRACE_FIELDS:
            if expected[field] != actual[field]:
                raise AssertionError(
                    f"retire {index} field {field}: "
                    f"reference=0x{expected[field]:x}, rtl=0x{actual[field]:x}; "
                    f"reference row={expected}; rtl row={actual}"
                )
    if len(reference) != len(rtl):
        side = "RTL" if len(rtl) > len(reference) else "reference"
        extra = rtl[common] if len(rtl) > common else reference[common]
        raise AssertionError(
            f"trace length mismatch: reference={len(reference)}, rtl={len(rtl)}; "
            f"first extra {side} row={extra}"
        )


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("reference_trace")
    parser.add_argument("rtl_trace")
    parser.add_argument("--name", default="cpu")
    args = parser.parse_args(argv)
    try:
        reference = read_trace(args.reference_trace)
        rtl = read_trace(args.rtl_trace)
        compare_traces(reference, rtl)
    except (OSError, ValueError, AssertionError) as error:
        print(f"{args.name} differential FAIL: {error}", file=sys.stderr)
        return 1
    print(f"{args.name} differential PASS: {len(reference)} retire events")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
