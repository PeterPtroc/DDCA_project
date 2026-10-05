"""Run the experimental firmware's UART DDR2/DMA diagnostic on a named port."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time


def expected_crc():
    crc = 0xffff
    for index in range(256):
        word = ((index * 0x9e3779b9) & 0xffffffff) ^ 0xa55a1357
        for byte in word.to_bytes(4, 'little'):
            crc ^= byte
            for _ in range(8):
                crc = (crc >> 1) ^ (0xa001 if crc & 1 else 0)
    return crc


def read_until(port, transcript, marker, timeout, need_crc=False):
    deadline = time.monotonic() + timeout
    found_crc = False
    while time.monotonic() < deadline:
        raw = port.readline()
        if not raw:
            continue
        line = raw.decode('ascii', errors='strict').strip()
        transcript.write(line + '\n')
        transcript.flush()
        print(line, flush=True)
        if 'FAIL' in line:
            raise RuntimeError(f'FPGA diagnostic failed: {line}')
        if line.startswith('DMA CRC '):
            if int(line[8:], 16) != expected_crc():
                raise RuntimeError(f'FPGA CRC differs from host oracle: {line}')
            found_crc = True
        if line == marker:
            if need_crc and not found_crc:
                raise RuntimeError('PASS arrived without a validated CRC')
            return
    raise TimeoutError(f'No {marker!r} within {timeout}s')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', required=True)
    parser.add_argument('--repeat', type=int, default=3)
    parser.add_argument('--timeout', type=float, default=30)
    parser.add_argument('--full', action='store_true', help='write/read the complete diagnostic-owned 128 MiB DDR')
    parser.add_argument('--full-timeout', type=float, default=1200)
    parser.add_argument('--output', type=Path, default=Path('build/ptrocos_hardware'))
    args = parser.parse_args()
    if args.repeat < 1 or args.timeout <= 0 or args.full_timeout <= 0:
        parser.error('repeat and timeouts must be positive')
    import serial
    args.output.mkdir(parents=True, exist_ok=True)
    record = dict(port=args.port, baud=115200, started_utc=datetime.now(timezone.utc).isoformat(),
                  crc=f'{expected_crc():04x}', selftests_passed=0, full_sweep_passed=False,
                  hardware_verified=False)
    try:
        with serial.Serial(args.port, 115200, timeout=1, write_timeout=3) as port, \
                (args.output / 'uart.log').open('w', encoding='ascii') as transcript:
            port.reset_input_buffer()
            for _ in range(args.repeat):
                port.write(b'r')
                read_until(port, transcript, 'DDR2 DMA PASS', args.timeout, need_crc=True)
                record['selftests_passed'] += 1
            if args.full:
                port.write(b'f')
                read_until(port, transcript, 'DDR2 FULL PASS', args.full_timeout)
                record['full_sweep_passed'] = True
            record['hardware_verified'] = True
    except Exception as exc:
        record['error'] = str(exc)
        raise
    finally:
        record['finished_utc'] = datetime.now(timezone.utc).isoformat()
        (args.output / 'result.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print('PTROCOS DDR2 HARDWARE PASS' + (' including full 128 MiB sweep' if args.full else ' (short diagnostic)'))


if __name__ == '__main__':
    main()
