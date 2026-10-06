"""Exercise the real UART TTY without requiring a keyboard or VGA monitor."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import time

import serial


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--output", type=Path, default=Path("build/ptrocos_shell_hardware"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    record = {"port": args.port, "started_utc": datetime.now(timezone.utc).isoformat(),
              "uart_shell_verified": False, "keyboard_physical_verified": False,
              "visual_display_verified": False, "checks": []}
    prompt = b"\r\x1b[2Kptroc> "
    try:
        with serial.Serial(args.port, 115200, timeout=0.02, write_timeout=3) as port, \
                (args.output / "uart.log").open("wb") as log:
            def read():
                data = port.read(max(1, port.in_waiting))
                if data:
                    log.write(data)
                    log.flush()
                if b"PTROCOS PANIC" in data:
                    raise RuntimeError("Firmware panic")
                return data

            def send(data):
                for byte in data:
                    port.write(bytes([byte]))
                    time.sleep(0.003)

            def until(predicate, timeout=8):
                received = bytearray()
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    received.extend(read())
                    if b"PTROCOS PANIC" in received:
                        raise RuntimeError(received.decode("ascii", errors="replace"))
                    if predicate(bytes(received)):
                        return bytes(received)
                raise TimeoutError(f"UART response timeout: {bytes(received)!r}")

            def exchange(name, data, expected):
                send(data)
                response = until(lambda value: expected in value and value.endswith(prompt))
                record["checks"].append(name)
                print(f"PASS {name}", flush=True)
                return response

            def command(name, expected):
                return exchange(name, name.encode("ascii") + b"\n", expected)

            port.reset_input_buffer()
            exchange("synchronize", b"\x03", b"^C\r\n")
            command("uname", b"\r\nPtrocOS RV32IM / FreeRTOS 11.3.1 / Nexys A7-100T\r\n")
            command("help", b"\r\nhelp echo clear uname uptime mem video kbd tasks sleep ddrtest\r\n")
            exchange("quoted arguments", b"echo 'quoted value' plain\\ word ''\n",
                     b"\r\nquoted value plain word \r\n")
            exchange("insert at cursor", b"echo ac\x1b[Db\n", b"\r\nabc\r\n")
            exchange("history", b"\x1b[A\n", b"\r\nabc\r\n")
            exchange("home", b"cho HOME\x01e\n", b"\r\nHOME\r\n")
            exchange("delete", b"echo axc\x1b[D\x1b[D\x1b[3~b\n", b"\r\nabc\r\n")
            exchange("completion", b"una\t\n", b"\r\nPtrocOS RV32IM / FreeRTOS 11.3.1 / Nexys A7-100T\r\n")
            send(b"\x1b[")
            time.sleep(0.15)
            command("echo ESC-TIMEOUT", b"\r\nESC-TIMEOUT\r\n")
            record["checks"].append("escape timeout")
            response = exchange("CRLF", b"echo ONCE\r\n", b"\r\nONCE\r\n")
            if response.count(b"\r\nONCE\r\n") != 1:
                raise AssertionError("CRLF executed twice")
            exchange("line bound", b"echo " + b"X" * 60 + b"\n",
                     b"\r\nline too long; discarded\r\n")
            command("echo RECOVERED", b"\r\nRECOVERED\r\n")
            command("echo 'unterminated", b"\r\nsyntax error: quotes, escape or argument limit\r\n")
            command("sleep 60001", b"\r\nusage: sleep 0..60000\r\n")

            send(b"sleep 1000\n")
            until(lambda value: b"sleeping; Ctrl+C cancels\r\n" in value)
            time.sleep(0.12)
            cancel_started = time.monotonic()
            send(b"\x03")
            cancelled = until(lambda value: b"^C cancelled\r\n" in value and value.endswith(prompt))
            if b"sleep done" in cancelled:
                raise AssertionError("sleep completed instead of cancelling")
            record["cancel_latency_seconds"] = time.monotonic() - cancel_started
            if record["cancel_latency_seconds"] > 0.5:
                raise AssertionError("Ctrl+C did not interrupt promptly")
            record["checks"].append("running command Ctrl+C")
            print("PASS running command Ctrl+C", flush=True)
            send(b"sleep 1000\n")
            until(lambda value: b"sleeping; Ctrl+C cancels\r\n" in value)
            lost = exchange("input queue loss recovery", b"echo " + b"Z" * 154 + b"\n",
                            b"\r\ninput lost; line discarded\r\n")
            if b"^C cancelled\r\n" not in lost or b"\r\nZZZ" in lost:
                raise AssertionError("Input loss did not abort and discard safely")
            command("echo LOSS-RECOVERED", b"\r\nLOSS-RECOVERED\r\n")
            record["expected_input_dropped"] = 1
            command("sleep 10", b"\r\nsleep done\r\n")
            for _ in range(3):
                command("ddrtest", b"\r\nDDR DMA PASS words=256 crc=0000f364\r\n")

            memory = command("mem", b" bram=65536 ddr=134217728\r\n")
            match = re.search(rb"\r\nheap_free=(\d+) heap_min=(\d+) bram=", memory)
            if not match or min(map(int, match.groups())) < 4096:
                raise AssertionError("Insufficient FreeRTOS heap")
            record["heap_free"], record["heap_min"] = map(int, match.groups())
            states = command("tasks", b"name priority state stack_free_words\r\n")
            # Consecutive rows share the CRLF boundary, so use line parsing.
            task_rows = [re.fullmatch(rb"(input|heartbeat|uart-tty|vga-tty|IDLE) (\d+) (\d+) (\d+)", row)
                         for row in states.split(b"\r\n")]
            task_rows = [row.groups() for row in task_rows if row]
            if len(task_rows) != 5 or min(int(row[3]) for row in task_rows) < 32:
                raise AssertionError(f"Missing tasks or exhausted stack: {task_rows}")
            record["tasks"] = [{"name": row[0].decode(), "priority": int(row[1]),
                                "state": int(row[2]), "stack_free_words": int(row[3])}
                               for row in task_rows]
            keyboard = command("kbd", b" recoveries=")
            match = re.search(rb"\r\nstatus=(\d+) received=(\d+) errors=(\d+) timeouts=(\d+) overflow=(\d+) edges=(\d+) recoveries=(\d+)\r\n", keyboard)
            if not match:
                raise AssertionError("Invalid keyboard diagnostic")
            record["keyboard_status"] = dict(zip("status received errors timeouts overflow edges recoveries".split(), map(int, match.groups())))
            command("clear", b"\x1b[2J\x1b[H")
            samples = []
            for _ in range(3):
                uptime = command("uptime", b" input_dropped=")
                match = re.search(rb"\r\nticks=(\d+) heartbeat=(\d+) io_polls=(\d+) input_dropped=(\d+)\r\n", uptime)
                if not match:
                    raise AssertionError("Invalid scheduler diagnostic")
                video = command("video", b" mode=640x480 text=80x30 pixel_hz=25200000\r\n")
                frames = re.search(rb"\r\nframes=(\d+) cursor=(\d+) mode=", video)
                if not frames:
                    raise AssertionError("Invalid video diagnostic")
                sample = dict(zip("ticks heartbeat io_polls input_dropped".split(), map(int, match.groups())))
                sample["frames"], sample["cursor"] = map(int, frames.groups())
                samples.append(sample)
                time.sleep(0.5)
            for earlier, later in zip(samples, samples[1:]):
                if later["input_dropped"] != record["expected_input_dropped"] or any(later[field] <= earlier[field] for field in ("ticks", "heartbeat", "io_polls", "frames")):
                    raise AssertionError(f"Scheduler or video stalled: {samples}")
            record["samples"] = samples
            record["uart_shell_verified"] = True
            print("PTROCOS SHELL HARDWARE PASS", flush=True)
    except Exception as error:
        record["error"] = str(error)
        raise
    finally:
        record["ended_utc"] = datetime.now(timezone.utc).isoformat()
        (args.output / "result.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
