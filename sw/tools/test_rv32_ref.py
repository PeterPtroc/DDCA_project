import unittest

from diff_trace import compare_traces
from rv32_ref import PASS_VALUE, RV32Reference, crc16_modbus_byte
from rv32asm import assemble


class ReferenceModelTests(unittest.TestCase):
    def test_crc_known_vector(self):
        crc = 0xFFFF
        for byte in b"123456789":
            crc = crc16_modbus_byte(crc, byte)
        self.assertEqual(crc, 0x4B37)

    def test_reference_reaches_pass_signature(self):
        words = assemble(
            [
                "addi t0, x0, 7",
                "addi t1, t0, -2",
                "add t2, t0, t1",
                "lui t0, 0x40000",
                "lui t1, 0x600d6",
                "addi t1, t1, 13",
                "sw t1, 12(t0)",
            ]
        )
        rows = RV32Reference(words).run()
        self.assertEqual(len(rows), 7)
        self.assertEqual(rows[2]["rd_data"], 12)
        self.assertEqual(rows[-1]["mem_data"], PASS_VALUE)

    def test_diff_reports_architectural_mismatch(self):
        row = {
            "step": 0,
            "pc": 0,
            "insn": 0x13,
            "rd_we": 0,
            "rd": 0,
            "rd_data": 0,
            "mem_we": 0,
            "mem_addr": 0,
            "mem_data": 0,
        }
        compare_traces([row], [dict(row)])
        changed = dict(row)
        changed["pc"] = 4
        with self.assertRaises(AssertionError):
            compare_traces([row], [changed])


if __name__ == "__main__":
    unittest.main()
