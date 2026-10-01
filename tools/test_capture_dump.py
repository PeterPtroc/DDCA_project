import tempfile
import unittest
from pathlib import Path

from capture_dump import (
    CaptureHeader,
    build_capture_packet,
    crc16_modbus,
    parse_capture_packet,
    read_capture,
    write_csv,
    write_vcd,
)


class CaptureDumpTests(unittest.TestCase):
    def test_crc_reference(self):
        self.assertEqual(crc16_modbus(b"123456789"), 0x4B37)

    def test_packet_crc_packing_csv_and_vcd(self):
        samples = ([0, 1, 1, 0, 0, 1, 0, 1] * 512)[:4096]
        header = CaptureHeader(2, 1, 4096, 5, 2048, 20, 6, 5_000_000)
        packet = build_capture_packet(header, samples)
        self.assertEqual(len(packet), 540)
        decoded_header, decoded_samples = parse_capture_packet(packet)
        self.assertEqual(decoded_header, header)
        self.assertEqual(decoded_samples, samples)

        damaged = bytearray(packet)
        damaged[30] ^= 1
        with self.assertRaisesRegex(ValueError, "CRC"):
            parse_capture_packet(bytes(damaged))

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packet_path = root / "capture.cap2"
            csv_path = root / "capture.csv"
            vcd_path = root / "capture.vcd"
            packet_path.write_bytes(packet)
            reread_header, reread_samples = read_capture(packet_path)
            self.assertEqual(reread_header, header)
            self.assertEqual(reread_samples, samples)
            write_csv(samples, csv_path)
            csv_header, csv_samples = read_capture(csv_path)
            self.assertIsNone(csv_header)
            self.assertEqual(csv_samples, samples)
            write_vcd(samples[:4], vcd_path, header.sample_div)
            text = vcd_path.read_text()
            self.assertIn("$var wire 1 ! scope", text)
            self.assertNotIn("ch7", text)
            self.assertIn("#150", text)


if __name__ == "__main__":
    unittest.main()
