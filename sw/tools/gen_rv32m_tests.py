#!/usr/bin/env python3
"""Reproducible arithmetic vectors and a standalone self-checking ISA image."""
import argparse
import random
from pathlib import Path
from rv32asm import assemble
from rv32m_ref import m_result

OPERATIONS = ("mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu")
EDGES = (0, 1, 2, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFE, 0xFFFFFFFF,
         0x55555555, 0xAAAAAAAA, 0xFFFF, 0x10000)


def encode_m(op, rd=7, rs1=5, rs2=6):
    return 0x02000033 | (rs2 << 20) | (rs1 << 15) | (op << 12) | (rd << 7)


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0x52563332)
    unit_pairs = [(a, b) for a in EDGES for b in EDGES]
    unit_pairs += [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(512)]
    vectors = [(op, a, b, m_result(op, a, b)) for a, b in unit_pairs for op in range(8)]
    (output / "vectors.txt").write_text(
        "".join(f"{op:x} {a:08x} {b:08x} {expected:08x}\n"
                for op, a, b, expected in vectors), encoding="ascii")

    # Keep the image in the existing 64 KiB instruction address window.
    pairs = [(a, b) for a in EDGES[:8] for b in EDGES[:8]]
    pairs += [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(48)]
    lines = ["lui s0, 0x10000", "lui s1, 0x40000"]
    for a, b in pairs:
        for op in range(8):
            expected = m_result(op, a, b)
            lines += [f"li t0, 0x{a:08x}", f"li t1, 0x{b:08x}",
                      f".word 0x{encode_m(op):08x}", f"li t3, 0x{expected:08x}",
                      "bne t2, t3, fail", "sw t2, 0(s0)", "lw t4, 0(s0)",
                      f".word 0x{encode_m(0, rd=29, rs1=29, rs2=6):08x}"]
    # Destination/source overlap, chained M consumers, x0 destination/source,
    # an immediate dependent branch/store, and a wrong-path M instruction.
    lines += ["li t0, 7", "li t1, -3",
              f".word 0x{encode_m(0, rd=5):08x}",
              f".word 0x{encode_m(4, rd=6, rs1=5, rs2=6):08x}",
              "li t3, 7", "bne t1, t3, fail", "sw t1, 4(s0)",
              f".word 0x{encode_m(0, rd=0):08x}", "bne x0, x0, fail",
              f".word 0x{encode_m(4, rd=7, rs1=0, rs2=0):08x}",
              "li t3, -1", "bne t2, t3, fail", "j pass",
              f".word 0x{encode_m(4):08x}",
              "fail: li t0, 0xbad00001", "sw t0, 12(s1)", "j fail",
              "pass: li t0, 0x600d600d", "sw t0, 12(s1)", "j pass"]
    # All failure branches must fit the 13-bit branch displacement. A nearby
    # trampoline per check avoids wrapping a far branch in the tiny assembler.
    expanded = []
    check = 0
    for line in lines:
        if line.startswith("bne ") and line.endswith(", fail"):
            operands = line[4:-6]
            expanded += [f"beq {operands}, check_{check}", "j fail", f"check_{check}: nop"]
            check += 1
        else:
            expanded.append(line)
    words = assemble(expanded)
    if len(words) > 16384:
        raise ValueError(f"ISA image exceeds 64 KiB: {len(words)} words")
    (output / "isa.S").write_text("\n".join(expanded) + "\n", encoding="ascii")
    (output / "isa.hex").write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")
    print(f"Generated {len(vectors)} unit vectors and {len(words)} ISA words")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    generate(parser.parse_args().output)
