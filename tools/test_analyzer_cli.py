import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from analyzer_cli import build_parser, transact
from capture_dump import HEADER, crc16_modbus


class SerialStub:
    def __init__(self, response=b""):
        self.response = io.BytesIO(response)
        self.commands = bytearray()
        self.flushed = False

    def write(self, value):
        self.commands.extend(value)

    def read(self, count):
        return self.response.read(min(count, 3))

    def readline(self):
        return self.response.readline()

    def flush(self):
        self.flushed = True


class AnalyzerClientTests(unittest.TestCase):
    def test_board_error_is_reported_without_waiting_for_cap2_header(self):
        link = SerialStub(b"ERR2 TIMEOUT\n")
        args = build_parser().parse_args(["--port", "COM9", "dump"])
        with self.assertRaisesRegex(RuntimeError, "capture failed: TIMEOUT"):
            transact(link, args)
        self.assertEqual(link.commands, b"d")

    def test_host_timeout_cancels_pending_acquisition(self):
        for response in (b"", b"CAP2\x02\x00"):
            with self.subTest(response=response):
                link = SerialStub(response)
                args = build_parser().parse_args(["--port", "COM9", "dump"])
                with self.assertRaises(TimeoutError):
                    transact(link, args)
                self.assertEqual(link.commands, b"dc")
                self.assertTrue(link.flushed)

    def test_cancel_reads_acknowledgement(self):
        link = SerialStub(b"ERR2 CANCELLED\n")
        args = build_parser().parse_args(["--port", "COM9", "cancel"])
        with contextlib.redirect_stdout(io.StringIO()) as output:
            transact(link, args)
        self.assertEqual(output.getvalue(), "ERR2 CANCELLED\n")
        self.assertEqual(link.commands, b"c")

    def test_successful_dump_preserves_packet_and_timebase(self):
        data = HEADER.pack(b"CAP2", 2, 0, 4096, 200, 2048, 1000, 500, 100000)
        data += bytes([0xAA]) * 512
        packet = data + crc16_modbus(data).to_bytes(2, "little")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = build_parser().parse_args([
                "--port", "COM9", "dump", "--output", str(root / "capture.csv"),
                "--vcd", str(root / "capture.vcd"), "--packet", str(root / "capture.cap2"),
            ])
            with contextlib.redirect_stdout(io.StringIO()) as output:
                transact(SerialStub(packet), args)
            self.assertEqual((root / "capture.cap2").read_bytes(), packet)
            self.assertIn("2000 ns/step", output.getvalue())
            self.assertTrue((root / "capture.csv").exists())
            self.assertTrue((root / "capture.vcd").exists())
