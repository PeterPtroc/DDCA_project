#!/usr/bin/env python3
"""Small two-pass assembler for the project's RV32I/custom instruction subset."""

import argparse
import re

REG = {
    "zero": 0,
    "ra": 1,
    "sp": 2,
    "gp": 3,
    "tp": 4,
    "t0": 5,
    "t1": 6,
    "t2": 7,
    **{f"s{i}": 8 + i for i in range(2)},
    **{f"a{i}": 10 + i for i in range(8)},
    "s2": 18,
    "s3": 19,
    "s4": 20,
    "s5": 21,
    "s6": 22,
    "s7": 23,
    "s8": 24,
    "s9": 25,
    "s10": 26,
    "s11": 27,
    "t3": 28,
    "t4": 29,
    "t5": 30,
    "t6": 31,
}
REG.update({f"x{i}": i for i in range(32)})

CSR = {
    "mstatus": 0x300,
    "misa": 0x301,
    "mie": 0x304,
    "mtvec": 0x305,
    "mscratch": 0x340,
    "mepc": 0x341,
    "mcause": 0x342,
    "mtval": 0x343,
    "mip": 0x344,
    "mcycle": 0xB00,
    "minstret": 0xB02,
    "mcycleh": 0xB80,
    "minstreth": 0xB82,
    "mhartid": 0xF14,
}


def reg(s):
    return REG[s.lower()]


def csr(s):
    return CSR.get(s.lower(), int(s, 0) if s.lower() not in CSR else CSR[s.lower()])


def num(s, labels, pc):
    if s == ".":
        return 0
    return labels[s] - pc if s in labels else int(s, 0)


def enc_r(f7, rs2, rs1, f3, rd, op=0x33):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def tokens(s):
    return [x for x in re.split(r"[ ,()]+", s) if x]


def expand_pseudo(s):
    p = tokens(s)
    m = p[0].lower()
    if m == "nop":
        return ["addi x0, x0, 0"]
    if m == "mv":
        return [f"addi {p[1]}, {p[2]}, 0"]
    if m == "li":
        imm = int(p[2], 0)
        if -2048 <= imm <= 2047:
            return [f"addi {p[1]}, x0, {imm}"]
        signed = imm & 0xFFFFFFFF
        if signed & 0x80000000:
            signed -= 0x100000000
        upper = (signed + 0x800) >> 12
        low = signed - (upper << 12)
        return [f"lui {p[1]}, {upper}", f"addi {p[1]}, {p[1]}, {low}"]
    if m == "j":
        return [f"jal x0, {p[1]}"]
    if m == "call":
        return [f"jal ra, {p[1]}"]
    if m == "ret":
        return ["jalr x0, 0(ra)"]
    if m == "la":
        return [f"lui {p[1]}, {p[2]}", f"addi {p[1]}, {p[1]}, {p[2]}"]
    if m == "csrr":
        return [f"csrrs {p[1]}, {p[2]}, x0"]
    if m == "csrw":
        return [f"csrrw x0, {p[1]}, {p[2]}"]
    if m == "csrs":
        return [f"csrrs x0, {p[1]}, {p[2]}"]
    if m == "csrc":
        return [f"csrrc x0, {p[1]}, {p[2]}"]
    return [s]


def assemble(lines):
    labels = {}
    clean = []
    pc = 0
    for raw in lines:
        s = raw.split("#", 1)[0].strip()
        while ":" in s:
            lab, s = s.split(":", 1)
            labels[lab.strip()] = pc
            s = s.strip()
        if s:
            for expanded in expand_pseudo(s):
                clean.append((pc, expanded))
                pc += 4

    out = []
    for pc, s in clean:
        p = tokens(s)
        m = p[0].lower()
        v = 0
        if m == ".word":
            v = int(p[1], 0)
        elif m in (
            "add",
            "sub",
            "sll",
            "slt",
            "sltu",
            "xor",
            "srl",
            "sra",
            "or",
            "and",
        ):
            f3 = {
                "add": 0,
                "sub": 0,
                "sll": 1,
                "slt": 2,
                "sltu": 3,
                "xor": 4,
                "srl": 5,
                "sra": 5,
                "or": 6,
                "and": 7,
            }[m]
            f7 = 0x20 if m in ("sub", "sra") else 0
            v = enc_r(f7, reg(p[3]), reg(p[2]), f3, reg(p[1]))
        elif m in (
            "addi",
            "slti",
            "sltiu",
            "xori",
            "ori",
            "andi",
            "slli",
            "srli",
            "srai",
        ):
            f3 = {
                "addi": 0,
                "slti": 2,
                "sltiu": 3,
                "xori": 4,
                "ori": 6,
                "andi": 7,
                "slli": 1,
                "srli": 5,
                "srai": 5,
            }[m]
            if p[3] in labels:
                absolute = labels[p[3]]
                upper = (absolute + 0x800) >> 12
                imm = absolute - (upper << 12)
            else:
                imm = int(p[3], 0)
            if m == "srai":
                imm |= 0x400
            v = (
                ((imm & 0xFFF) << 20)
                | (reg(p[2]) << 15)
                | (f3 << 12)
                | (reg(p[1]) << 7)
                | 0x13
            )
        elif m in ("lb", "lh", "lw", "lbu", "lhu", "sb", "sh", "sw"):
            imm = int(p[2], 0)
            rs1 = reg(p[3])
            rs2_or_rd = reg(p[1])
            if m in ("lb", "lh", "lw", "lbu", "lhu"):
                f3 = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}[m]
                v = (
                    ((imm & 0xFFF) << 20)
                    | (rs1 << 15)
                    | (f3 << 12)
                    | (rs2_or_rd << 7)
                    | 3
                )
            else:
                f3 = {"sb": 0, "sh": 1, "sw": 2}[m]
                v = (
                    (((imm >> 5) & 0x7F) << 25)
                    | (rs2_or_rd << 20)
                    | (rs1 << 15)
                    | (f3 << 12)
                    | ((imm & 0x1F) << 7)
                    | 0x23
                )
        elif m in ("lui", "auipc"):
            if p[2] in labels:
                immediate = (labels[p[2]] + 0x800) >> 12
            else:
                immediate = int(p[2], 0)
            v = (
                ((immediate & 0xFFFFF) << 12)
                | (reg(p[1]) << 7)
                | (0x37 if m == "lui" else 0x17)
            )
        elif m in ("beq", "bne", "blt", "bge", "bltu", "bgeu"):
            imm = num(p[3], labels, pc)
            f3 = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}[m]
            v = (
                (((imm >> 12) & 1) << 31)
                | (((imm >> 5) & 0x3F) << 25)
                | (reg(p[2]) << 20)
                | (reg(p[1]) << 15)
                | (f3 << 12)
                | (((imm >> 1) & 0xF) << 8)
                | (((imm >> 11) & 1) << 7)
                | 0x63
            )
        elif m == "jal":
            imm = num(p[2], labels, pc)
            v = (
                (((imm >> 20) & 1) << 31)
                | (((imm >> 1) & 0x3FF) << 21)
                | (((imm >> 11) & 1) << 20)
                | (((imm >> 12) & 0xFF) << 12)
                | (reg(p[1]) << 7)
                | 0x6F
            )
        elif m == "jalr":
            try:
                imm = int(p[2], 0)
                rs1 = reg(p[3])
            except (ValueError, KeyError):
                rs1 = reg(p[2])
                imm = int(p[3], 0)
            v = ((imm & 0xFFF) << 20) | (rs1 << 15) | (reg(p[1]) << 7) | 0x67
        elif m == "crc16.b":
            v = (reg(p[3]) << 20) | (reg(p[2]) << 15) | (reg(p[1]) << 7) | 0x0B
        elif m in ("csrrw", "csrrs", "csrrc"):
            f3 = {"csrrw": 1, "csrrs": 2, "csrrc": 3}[m]
            v = (csr(p[2]) << 20) | (reg(p[3]) << 15) | (f3 << 12) | \
                (reg(p[1]) << 7) | 0x73
        elif m in ("csrrwi", "csrrsi", "csrrci"):
            f3 = {"csrrwi": 5, "csrrsi": 6, "csrrci": 7}[m]
            v = (csr(p[2]) << 20) | ((int(p[3], 0) & 0x1F) << 15) | \
                (f3 << 12) | (reg(p[1]) << 7) | 0x73
        elif m == "ecall":
            v = 0x00000073
        elif m == "ebreak":
            v = 0x00100073
        elif m == "mret":
            v = 0x30200073
        elif m == "fence":
            v = 0x0FF0000F
        elif m == "fence.i":
            v = 0x0000100F
        else:
            raise ValueError(f"unsupported instruction: {s}")
        out.append(v & 0xFFFFFFFF)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    args = ap.parse_args()
    with open(args.input) as f:
        words = assemble(f.readlines())
    with open(args.output, "w") as f:
        f.write("\n".join(f"{w:08x}" for w in words) + "\n")
