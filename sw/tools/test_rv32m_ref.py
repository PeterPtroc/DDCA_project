import unittest
from rv32m_ref import RV32MReference, m_result
from gen_rv32m_tests import encode_m


class MReferenceTests(unittest.TestCase):
    def test_specification_boundaries(self):
        for op in (4, 5):
            self.assertEqual(m_result(op, 0x80000000, 0), 0xFFFFFFFF)
        for op in (6, 7):
            self.assertEqual(m_result(op, 0x80000000, 0), 0x80000000)
        self.assertEqual(m_result(4, 0x80000000, 0xFFFFFFFF), 0x80000000)
        self.assertEqual(m_result(6, 0x80000000, 0xFFFFFFFF), 0)
        self.assertEqual(m_result(4, -7, 3), 0xFFFFFFFE)
        self.assertEqual(m_result(6, -7, 3), 0xFFFFFFFF)
        self.assertEqual(m_result(4, 7, -3), 0xFFFFFFFE)
        self.assertEqual(m_result(6, 7, -3), 1)
        self.assertEqual(m_result(1, -1, -1), 0)
        self.assertEqual(m_result(2, -1, 0xFFFFFFFF), 0xFFFFFFFF)
        self.assertEqual(m_result(3, 0xFFFFFFFF, 0xFFFFFFFF), 0xFFFFFFFE)

    def test_encoding_and_zero_register(self):
        self.assertEqual(encode_m(0, 1, 2, 3), 0x023100B3)
        self.assertEqual(encode_m(7, 1, 2, 3), 0x023170B3)
        machine = RV32MReference([encode_m(4, 0, 0, 0)])
        row, done = machine.step()
        self.assertEqual(machine.regs[0], 0)
        self.assertEqual((row['rd_we'], row['rd'], row['rd_data']), (0, 0, 0))
        self.assertFalse(done)


if __name__ == '__main__':
    unittest.main()
