import tempfile
import unittest
from pathlib import Path

from capture_dump import read_capture, write_csv, write_vcd


class CaptureDumpTests(unittest.TestCase):
    def test_binary_csv_and_vcd(self):
        samples = [0x00, 0x01, 0x03, 0x02]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "capture.bin"
            csv_path = root / "capture.csv"
            vcd_path = root / "capture.vcd"
            binary.write_bytes(bytes(samples))
            self.assertEqual(read_capture(binary), samples)
            write_csv(samples, csv_path)
            self.assertEqual(read_capture(csv_path), samples)
            write_vcd(samples, vcd_path, 10_000_000)
            text = vcd_path.read_text()
            self.assertIn("$timescale 1ns", text)
            self.assertIn("#300", text)
            self.assertIn("ch7", text)


if __name__ == "__main__":
    unittest.main()
