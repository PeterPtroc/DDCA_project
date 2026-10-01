import unittest

from rv32asm import assemble


class AssemblerTests(unittest.TestCase):
    def test_li_and_mv(self):
        words = assemble(
            [
                "li t0, 42",
                "li t1, 0x12345678",
                "mv t2, t1",
            ]
        )
        self.assertEqual(words[0], 0x02A00293)
        self.assertEqual(words[1:3], [0x12345337, 0x67830313])
        self.assertEqual(words[3], 0x00030393)

    def test_standard_jalr_form(self):
        self.assertEqual(assemble(["jalr x0, 0(ra)"])[0], 0x00008067)
        self.assertEqual(assemble(["jalr x0, ra, 0"])[0], 0x00008067)

    def test_labels_are_counted_after_pseudo_expansion(self):
        words = assemble(
            [
                "j target",
                "li t0, 0x12345678",
                "target: nop",
            ]
        )
        self.assertEqual(len(words), 4)
        self.assertNotEqual(words[0], 0)


if __name__ == "__main__":
    unittest.main()
