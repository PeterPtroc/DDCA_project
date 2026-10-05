#!/usr/bin/env python3
"""Independent M semantics using Python integer arithmetic, not RTL iteration."""
import argparse
from rv32_ref import RV32Reference, load_hex, s32, u32, write_trace


def m_result(op, a, b):
    a, b = u32(a), u32(b)
    if op == 0:
        return u32(a * b)
    if op == 1:
        return u32((s32(a) * s32(b)) >> 32)
    if op == 2:
        return u32((s32(a) * b) >> 32)
    if op == 3:
        return u32((a * b) >> 32)
    if op not in (4, 5, 6, 7):
        raise ValueError(f"invalid M operation {op}")
    if b == 0:
        return a if op in (6, 7) else 0xFFFFFFFF
    if op in (5, 7):
        return a // b if op == 5 else a % b
    dividend, divisor = s32(a), s32(b)
    quotient = abs(dividend) // abs(divisor)
    if (dividend < 0) != (divisor < 0):
        quotient = -quotient
    return u32(quotient if op == 4 else dividend - quotient * divisor)


class RV32MReference(RV32Reference):
    def step(self):
        insn = self.imem[self.pc >> 2]
        if insn & 0xFE00007F != 0x02000033:
            return super().step()
        rd, op = (insn >> 7) & 31, (insn >> 12) & 7
        a, b = self.regs[(insn >> 15) & 31], self.regs[(insn >> 20) & 31]
        result = m_result(op, a, b)
        row = dict(step=self.step_count, pc=self.pc, insn=insn,
                   rd_we=int(rd != 0), rd=rd, rd_data=result if rd else 0,
                   mem_we=0, mem_addr=0, mem_data=0)
        if rd:
            self.regs[rd] = result
        self.regs[0] = 0
        self.pc = u32(self.pc + 4)
        self.step_count += 1
        return row, False


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("hex_file")
    parser.add_argument("trace_file")
    args = parser.parse_args()
    rows = RV32MReference(load_hex(args.hex_file)).run()
    write_trace(args.trace_file, rows)
    print(f"RV32M REFERENCE PASS: {len(rows)} retire events")
