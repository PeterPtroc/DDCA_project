"""Validate real DDR scanout counters and UART control without a VGA monitor."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import time
import serial

PROMPT = b"\r\x1b[2Kptroc> "
INFO = re.compile(rb"gfx 640x480 RGB565 stride=1280 status=(\d+) front=(\d+) frames=(\d+) swaps=(\d+) underruns=(\d+) beats=(\d+) errors=(\d+)\r\n")
FIELDS = ("status", "front", "frames", "swaps", "underruns", "beats", "errors")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--output", type=Path, default=Path("build/ptrocos_graphics_hardware"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    record = {"port": args.port, "started_utc": datetime.now(timezone.utc).isoformat(),
              "graphics_uart_verified": False, "visual_display_verified": False,
              "keyboard_physical_verified": False, "checks": [], "samples": []}
    try:
        with serial.Serial(args.port, 115200, timeout=0.02, write_timeout=3) as port, \
                (args.output / "uart.log").open("wb") as log:
            def send(value):
                for byte in value:
                    port.write(bytes([byte]))
                    time.sleep(0.003)

            def until(predicate, timeout=12):
                response = bytearray()
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    data = port.read(max(1, port.in_waiting))
                    if data:
                        response.extend(data); log.write(data); log.flush()
                    if b"PTROCOS PANIC" in response:
                        raise AssertionError("Firmware panic")
                    if predicate(bytes(response)):
                        return bytes(response)
                raise TimeoutError(f"UART graphics timeout: {bytes(response)!r}")

            def mark(name):
                record["checks"].append(name)
                print(f"PASS {name}", flush=True)

            def command(value, expected):
                send(value.encode("ascii") + b"\r")
                return until(lambda response: expected in response and response.endswith(PROMPT))

            def info():
                response = command("gfx info", b"gfx 640x480 RGB565")
                match = INFO.search(response)
                if not match:
                    raise AssertionError(f"Invalid graphics info: {response!r}")
                sample = dict(zip(FIELDS, map(int, match.groups())))
                sample["host_time"] = time.monotonic()
                record["samples"].append(sample)
                return sample

            def healthy(sample, enabled):
                if sample["status"] != int(enabled) or sample["underruns"] or sample["errors"]:
                    raise AssertionError(f"Unhealthy graphics: {sample}")

            port.reset_input_buffer()
            send(b"\x03")
            until(lambda response: b"^C\r\n" in response and response.endswith(PROMPT))
            command("gfx off", b"gfx text mode\r\n")
            command("gfx clear", b"gfx sticky errors cleared\r\n")
            initial = info(); healthy(initial, False)
            mark("text mode and initial counters")
            for bad in ("gfx pattern 2", "gfx pattern -1", "gfx pattern 4294967296", "gfx pattern 0 extra"):
                command(bad, b"usage: gfx info | pattern 0..1 | off | clear\r\n")
            invalid = info()
            if invalid["front"] != initial["front"] or invalid["swaps"] != initial["swaps"]:
                raise AssertionError("Invalid command changed front buffer")
            mark("invalid pattern commands preserve front buffer")
            command("gfx pattern 0", b"gfx pattern=0 displayed\r\n")
            time.sleep(0.08)
            first = info(); healthy(first, True)
            expected_front = 0x81100000 if initial["front"] == 0x81000000 else 0x81000000
            if first["front"] != expected_front or first["swaps"] != initial["swaps"] + 1:
                raise AssertionError("First buffer flip failed")
            mark("full RGB565 color-bars buffer flip")
            send(b"gfx pattern 1\r")
            until(lambda response: b"gfx drawing; Ctrl+C cancels\r\n" in response)
            began = time.monotonic(); send(b"\x03")
            until(lambda response: b"^C cancelled\r\n" in response and response.endswith(PROMPT))
            record["cancel_latency_seconds"] = time.monotonic() - began
            if record["cancel_latency_seconds"] > 0.5:
                raise AssertionError("Drawing cancellation was not responsive")
            cancelled = info(); healthy(cancelled, True)
            if cancelled["front"] != first["front"] or cancelled["swaps"] != first["swaps"]:
                raise AssertionError("Cancelled drawing changed front buffer")
            mark("Ctrl+C preserves displayed buffer")
            command("gfx pattern 1", b"gfx pattern=1 displayed\r\n")
            time.sleep(0.08)
            second = info(); healthy(second, True)
            if second["front"] == first["front"] or second["swaps"] != first["swaps"] + 1:
                raise AssertionError("Second buffer flip failed")
            mark("full RGB565 gradient buffer flip")
            for trial in range(3):
                command("ddrtest", b"DDR DMA PASS words=256 crc=0000f364\r\n")
                healthy(info(), True)
                mark(f"CPU and DDR DMA during scanout {trial+1}")
            before = info(); time.sleep(1.0); after = info()
            healthy(after, True)
            seconds = after["host_time"] - before["host_time"]
            record["frames_per_second"] = (after["frames"] - before["frames"]) / seconds
            record["scanout_bytes_per_second"] = (after["beats"] - before["beats"]) * 16 / seconds
            if not 50 < record["frames_per_second"] < 70 or not 30_000_000 < record["scanout_bytes_per_second"] < 43_000_000:
                raise AssertionError("DDR scanout rate does not match 640x480 at 60 Hz")
            mark("60 Hz frame events and RGB565 DDR bandwidth")
            uptime = command("uptime", b"input_dropped=")
            match = re.search(rb"ticks=(\d+) heartbeat=(\d+) io_polls=(\d+) input_dropped=(\d+)", uptime)
            if not match or int(match[4]) or min(map(int, match.groups()[:3])) <= 0:
                raise AssertionError("Scheduler or input loss during graphics")
            record["uptime"] = dict(zip(("ticks", "heartbeat", "io_polls", "input_dropped"), map(int, match.groups())))
            mark("scheduler and UART input remain responsive")
            command("gfx off", b"gfx text mode\r\n")
            disabled = info(); healthy(disabled, False)
            time.sleep(0.08); stopped = info()
            if stopped["beats"] != disabled["beats"]:
                raise AssertionError("DDR reader continued after text mode returned")
            command("echo GRAPHICS-TEXT-OK", b"\r\nGRAPHICS-TEXT-OK\r\n")
            mark("text mode return stops DDR scanout")
            record["graphics_uart_verified"] = True
        print("PTROCOS GRAPHICS HARDWARE PASS", flush=True)
    except Exception as error:
        record["failure"] = repr(error)
        raise
    finally:
        record["finished_utc"] = datetime.now(timezone.utc).isoformat()
        (args.output / "result.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
