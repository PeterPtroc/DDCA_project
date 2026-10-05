"""Read real-board video/PS2 diagnostics and optionally record physical key input."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import time
import serial

parser = argparse.ArgumentParser()
parser.add_argument("--port", required=True)
parser.add_argument("--listen-seconds", type=float, default=0)
parser.add_argument("--output", type=Path, default=Path("build/ptrocos_text_hardware"))
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
record = {"port": args.port, "started_utc": datetime.now(timezone.utc).isoformat(),
          "video_status_verified": False, "keyboard_physical_input_observed": False,
          "visual_display_verified": False, "status": [], "keys": []}
status_re = re.compile(r"VIDEO frames=([0-9a-f]{8}) cursor=([0-9a-f]{8}) ticks=([0-9a-f]{8}) PS2 status=([0-9a-f]{8}) rx=([0-9a-f]{8}) errors=([0-9a-f]{8}) timeout=([0-9a-f]{8}) overflow=([0-9a-f]{8}) clock_edges=([0-9a-f]{8})")
names = "frames cursor ticks ps2_status received errors timeout overflow clock_edges".split()
try:
    with serial.Serial(args.port,115200,timeout=0.25,write_timeout=3) as port, \
            (args.output / "uart.log").open("wb") as log:
        def read_line():
            data=port.readline()
            if not data: return ""
            log.write(data);log.flush()
            line=data.decode("ascii",errors="strict").strip()
            print(line,flush=True)
            if "FAIL" in line or "RECOVER" in line: raise RuntimeError(line)
            if line.startswith("KEY "):
                record["keys"].append(int(line[4:],16))
                record["keyboard_physical_input_observed"] = True
            match=status_re.fullmatch(line)
            if match:
                item=dict(zip(names,(int(value,16) for value in match.groups())))
                item["observed_monotonic"] = time.monotonic()
                if item["errors"] or item["timeout"] or item["overflow"] or item["ps2_status"] & 14:
                    raise RuntimeError(f"PS2 transport error: {item}")
                record["status"].append(item)
            return line
        # Boot output may already be complete. A status command independently
        # proves that CPU firmware, pixel-domain mailbox and frame engine run.
        port.reset_input_buffer()
        for index in range(3):
            before=len(record["status"])
            port.write(b"v")
            deadline=time.monotonic()+3
            while len(record["status"])==before:
                if time.monotonic()>deadline: raise TimeoutError("No video status response")
                read_line()
            if index<2: time.sleep(0.5)
        first,last=record["status"][0],record["status"][-1]
        frames=(last["frames"]-first["frames"]) & 0xffffffff
        elapsed=last["observed_monotonic"]-first["observed_monotonic"]
        record["observed_frame_hz"]=frames/elapsed
        if not 55 <= record["observed_frame_hz"] <= 65: raise RuntimeError("Video frame rate outside acceptance range")
        if last["ticks"]<=first["ticks"]: raise RuntimeError("Timer interrupts not advancing")
        record["video_status_verified"]=True
        print("VIDEO STATUS PASS",flush=True)
        if args.listen_seconds>0: print("Listening for physical PS/2 input",flush=True)
        end=time.monotonic()+args.listen_seconds
        next_status=time.monotonic()+5
        while time.monotonic()<end:
            read_line()
            if time.monotonic()>=next_status:
                port.write(b"v");next_status=time.monotonic()+5
        print(f"TEXT HARDWARE PASS frames_hz={record['observed_frame_hz']:.3f} key_events={len(record['keys'])}",flush=True)
except Exception as error:
    record["error"]=str(error)
    raise
finally:
    record["ended_utc"]=datetime.now(timezone.utc).isoformat()
    (args.output / "result.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
