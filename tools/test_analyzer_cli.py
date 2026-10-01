#!/usr/bin/env python3
"""Focused tests for serial response handling in analyzer_cli."""

from __future__ import annotations

import unittest

from analyzer_cli import read_line


class FakeLink:
    def __init__(self, response: bytes):
        self.response = response

    def readline(self) -> bytes:
        return self.response


class AnalyzerCliTests(unittest.TestCase):
    def test_read_line_returns_response(self) -> None:
        self.assertEqual(read_line(FakeLink(b"SCP2\n")), b"SCP2\n")

    def test_read_line_rejects_timeout(self) -> None:
        with self.assertRaisesRegex(TimeoutError, "waiting for line response"):
            read_line(FakeLink(b""))


if __name__ == "__main__":
    unittest.main()
