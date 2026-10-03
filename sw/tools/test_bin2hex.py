import tempfile
import unittest
from pathlib import Path

from bin2hex import convert


class Bin2HexTests(unittest.TestCase):
    def test_little_endian_words_and_padding(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "image.bin"
            output = Path(directory) / "image.hex"
            source.write_bytes(bytes([1, 2, 3, 4, 5]))
            self.assertEqual(convert(source, output), 2)
            self.assertEqual(output.read_text(), "04030201\n00000005\n")

    def test_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "image.bin"
            output = Path(directory) / "image.hex"
            source.write_bytes(bytes(5))
            with self.assertRaises(ValueError):
                convert(source, output, limit=4)


if __name__ == "__main__":
    unittest.main()

