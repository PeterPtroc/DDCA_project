#!/usr/bin/env python3
"""Independent architectural interpreter for the implemented RV32 subset."""

import argparse
import csv
import sys
from pathlib import Path

DATA_BASE = 0x10000000
DATA_SIZE = 4096
TEST_RESULT = 0x4000000C
PASS_VALUE = 0x600D600D
TRACE_FIELDS = (
    "step",
    "pc",
    "insn",
    "rd_we",
    "rd",
    "rd_data",
    "mem_we",
    "mem_addr",
    "mem_data",
)


def u32(value):
    return value & 0xFFFFFFFF


def s32(value):
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


def sext(value, bits):
    sign = 1 << (bits - 1)
    return (value ^ sign) - sign


def crc16_modbus_byte(crc, data):
    crc &= 0xFFFF
    data &= 0xFF
    for bit in range(8):
        if (crc & 1) ^ ((data >> bit) & 1):
            crc = (crc >> 1) ^ 0xA001
        else:
            crc >>= 1
    return crc


def load_hex(path):
    words = []
    for raw in Path(path).read_text(encoding="ascii").splitlines():
        text = raw.split("#", 1)[0].strip()
        if text:
            words.append(int(text, 16) & 0xFFFFFFFF)
    return words


class RV32Reference:
    def __init__(self, words):
        self.imem = list(words) + [0x00000013] * (2048 - len(words))
        self.regs = [0] * 32
        self.memory = {}
        self.pc = 0
        self.step_count = 0
        self.test_result = None

    def load_word(self, addr):
        if addr & 3:
            raise ValueError(f"misaligned load at 0x{addr:08x}")
        if DATA_BASE <= addr < DATA_BASE + DATA_SIZE:
            return self.memory.get(addr, 0)
        return 0

    def store_word(self, addr, value):
        if addr & 3:
            raise ValueError(f"misaligned store at 0x{addr:08x}")
        if DATA_BASE <= addr < DATA_BASE + DATA_SIZE:
            self.memory[addr] = u32(value)
        if addr == TEST_RESULT:
            self.test_result = u32(value)

    def step(self):
        if self.pc & 3 or self.pc // 4 >= len(self.imem):
            raise ValueError(f"invalid PC 0x{self.pc:08x}")

        pc = self.pc
        insn = self.imem[pc >> 2]
        opcode = insn & 0x7F
        rd = (insn >> 7) & 0x1F
        funct3 = (insn >> 12) & 7
        rs1 = (insn >> 15) & 0x1F
        rs2 = (insn >> 20) & 0x1F
        funct7 = (insn >> 25) & 0x7F
        a = self.regs[rs1]
        b = self.regs[rs2]
        next_pc = u32(pc + 4)
        write_enable = False
        write_value = 0
        mem_we = False
        mem_addr = 0
        mem_data = 0

        if opcode == 0x33:
            write_enable = True
            shamt = b & 0x1F
            key = (funct7, funct3)
            operations = {
                (0x00, 0): lambda: a + b,
                (0x20, 0): lambda: a - b,
                (0x00, 1): lambda: a << shamt,
                (0x00, 2): lambda: int(s32(a) < s32(b)),
                (0x00, 3): lambda: int(a < b),
                (0x00, 4): lambda: a ^ b,
                (0x00, 5): lambda: a >> shamt,
                (0x20, 5): lambda: s32(a) >> shamt,
                (0x00, 6): lambda: a | b,
                (0x00, 7): lambda: a & b,
            }
            if key not in operations:
                raise ValueError(f"unsupported R instruction 0x{insn:08x}")
            write_value = u32(operations[key]())
        elif opcode == 0x13:
            write_enable = True
            imm = sext(insn >> 20, 12)
            shamt = (insn >> 20) & 0x1F
            if funct3 == 0:
                write_value = u32(a + imm)
            elif funct3 == 2:
                write_value = int(s32(a) < imm)
            elif funct3 == 3:
                write_value = int(a < u32(imm))
            elif funct3 == 4:
                write_value = u32(a ^ imm)
            elif funct3 == 6:
                write_value = u32(a | imm)
            elif funct3 == 7:
                write_value = u32(a & imm)
            elif funct3 == 1 and funct7 == 0:
                write_value = u32(a << shamt)
            elif funct3 == 5 and funct7 == 0:
                write_value = a >> shamt
            elif funct3 == 5 and funct7 == 0x20:
                write_value = u32(s32(a) >> shamt)
            else:
                raise ValueError(f"unsupported I instruction 0x{insn:08x}")
        elif opcode == 0x03 and funct3 == 2:
            mem_addr = u32(a + sext(insn >> 20, 12))
            write_enable = True
            write_value = self.load_word(mem_addr)
        elif opcode == 0x23 and funct3 == 2:
            imm = ((insn >> 25) << 5) | ((insn >> 7) & 0x1F)
            mem_addr = u32(a + sext(imm, 12))
            mem_data = b
            mem_we = True
            self.store_word(mem_addr, mem_data)
        elif opcode == 0x63:
            imm = (
                ((insn >> 31) & 1) << 12
                | ((insn >> 7) & 1) << 11
                | ((insn >> 25) & 0x3F) << 5
                | ((insn >> 8) & 0xF) << 1
            )
            comparisons = {
                0: a == b,
                1: a != b,
                4: s32(a) < s32(b),
                5: s32(a) >= s32(b),
                6: a < b,
                7: a >= b,
            }
            if funct3 not in comparisons:
                raise ValueError(f"unsupported branch 0x{insn:08x}")
            if comparisons[funct3]:
                next_pc = u32(pc + sext(imm, 13))
        elif opcode == 0x37:
            write_enable = True
            write_value = insn & 0xFFFFF000
        elif opcode == 0x17:
            write_enable = True
            write_value = u32(pc + (insn & 0xFFFFF000))
        elif opcode == 0x6F:
            imm = (
                ((insn >> 31) & 1) << 20
                | ((insn >> 12) & 0xFF) << 12
                | ((insn >> 20) & 1) << 11
                | ((insn >> 21) & 0x3FF) << 1
            )
            write_enable = True
            write_value = u32(pc + 4)
            next_pc = u32(pc + sext(imm, 21))
        elif opcode == 0x67 and funct3 == 0:
            write_enable = True
            write_value = u32(pc + 4)
            next_pc = u32(a + sext(insn >> 20, 12)) & 0xFFFFFFFE
        elif opcode == 0x0B and funct3 == 0 and funct7 == 0:
            write_enable = True
            write_value = crc16_modbus_byte(a, b)
        else:
            raise ValueError(f"unsupported instruction at 0x{pc:08x}: 0x{insn:08x}")

        arch_rd_we = write_enable and rd != 0
        if arch_rd_we:
            self.regs[rd] = u32(write_value)
        self.regs[0] = 0
        self.pc = next_pc

        row = {
            "step": self.step_count,
            "pc": pc,
            "insn": insn,
            "rd_we": int(arch_rd_we),
            "rd": rd if arch_rd_we else 0,
            "rd_data": u32(write_value) if arch_rd_we else 0,
            "mem_we": int(mem_we),
            "mem_addr": mem_addr if mem_we else 0,
            "mem_data": u32(mem_data) if mem_we else 0,
        }
        self.step_count += 1
        return row, mem_we and mem_addr == TEST_RESULT

    def run(self, max_steps=100000):
        rows = []
        for _ in range(max_steps):
            row, done = self.step()
            rows.append(row)
            if done:
                if self.test_result != PASS_VALUE:
                    raise RuntimeError(
                        f"firmware reported FAIL 0x{self.test_result:08x}"
                    )
                return rows
        raise RuntimeError(f"reference timeout after {max_steps} instructions")


def write_trace(path, rows):
    with Path(path).open("w", newline="", encoding="ascii") as handle:
        writer = csv.DictWriter(handle, fieldnames=TRACE_FIELDS)
        writer.writeheader()
        for row in rows:
            formatted = dict(row)
            for field in ("pc", "insn", "rd_data", "mem_addr", "mem_data"):
                formatted[field] = f"{row[field]:08x}"
            writer.writerow(formatted)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("hex_file")
    parser.add_argument("trace_file")
    parser.add_argument("--max-steps", type=int, default=100000)
    args = parser.parse_args(argv)
    try:
        rows = RV32Reference(load_hex(args.hex_file)).run(args.max_steps)
        write_trace(args.trace_file, rows)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"reference error: {error}", file=sys.stderr)
        return 1
    print(f"REFERENCE PASS: {len(rows)} retire events")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
