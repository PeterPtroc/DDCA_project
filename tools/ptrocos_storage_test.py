"""Read-only board acceptance: UART mount and file CRC against a local original."""
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import re
import time
import serial

def crc16(data):
    crc=0xffff
    for byte in data:
        crc^=byte
        for _ in range(8): crc=(crc>>1)^(0xa001 if crc&1 else 0)
    return crc

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--port',required=True)
    parser.add_argument('--file',help='Existing card path; no writes or formatting')
    parser.add_argument('--expected',type=Path,help='Local original for independent byte count and CRC')
    parser.add_argument('--repeat',type=int,default=3)
    parser.add_argument('--files',action='store_true',help='Also verify ls, raw binary cat and bounded hexdump')
    parser.add_argument('--output',type=Path,default=Path('build/ptrocos_storage_hardware'))
    args=parser.parse_args()
    if bool(args.file)!=bool(args.expected): parser.error('--file and --expected must be supplied together')
    if args.repeat<1: parser.error('--repeat must be positive')
    if args.files and not args.file: parser.error('--files requires --file and --expected')
    if args.file and (len(args.file)>45 or any(ord(c)<32 or ord(c)>126 or c in "'\\" for c in args.file)):
        parser.error('Path must fit the ASCII TTY line and exclude quotes/backslash/control characters')
    args.output.mkdir(parents=True,exist_ok=True)
    expected=args.expected.read_bytes() if args.expected else None
    record={'started_utc':datetime.now(timezone.utc).isoformat(),'port':args.port,
        'mount_verified':False,'file_verified':False,'physical_keyboard_verified':False,'writes_performed':False,'checks':[]}
    prompt=b'\r\x1b[2Kptroc> '
    try:
        with serial.Serial(args.port,115200,timeout=.02,write_timeout=3) as port,(args.output/'uart.log').open('wb') as log:
            def exchange(command,wanted,timeout=20):
                for byte in command:
                    port.write(bytes([byte]));time.sleep(.003)
                data=bytearray();deadline=time.monotonic()+timeout
                while time.monotonic()<deadline:
                    part=port.read(max(1,port.in_waiting));log.write(part);log.flush();data.extend(part)
                    if b'PTROCOS PANIC' in data: raise RuntimeError('Firmware panic')
                    if wanted in data and data.endswith(prompt): return bytes(data)
                    if b'FatFs error=' in data and data.endswith(prompt): raise RuntimeError(bytes(data).decode(errors='replace'))
                raise TimeoutError(f'UART storage timeout: {bytes(data)!r}')
            def command(text,wanted,timeout=20):
                response=exchange(text.encode('utf-8')+b'\n',wanted,timeout)
                record['checks'].append(text);print(f'PASS {text}',flush=True);return response
            def raw_cat(text):
                for byte in text.encode('ascii')+b'\n':
                    port.write(bytes([byte]));time.sleep(.003)
                received=bytearray();deadline=time.monotonic()+max(30,len(expected)*10/115200+20)
                body_start=None;total=None
                while time.monotonic()<deadline:
                    part=port.read(max(1,port.in_waiting));log.write(part);log.flush();received.extend(part)
                    if body_start is None and b'\r\n' in received:
                        body_start=received.index(b'\r\n')+2;total=body_start+len(expected)+len(prompt)
                    if total is not None and len(received)>=total:
                        if len(received)!=total or received[body_start:body_start+len(expected)]!=expected or received[-len(prompt):]!=prompt:
                            raise AssertionError('Raw cat bytes/prompt mismatch')
                        record['checks'].append(text);print(f'PASS binary {text}',flush=True);return
                raise TimeoutError('Raw cat did not return the complete file and prompt')
            port.reset_input_buffer();exchange(b'\x03',b'^C\r\n')
            command('uname',b'PtrocOS RV32IM')
            info=command('help',b'fscheck')
            if b'mount umount sdinfo fscheck' not in info: raise AssertionError('Storage firmware required')
            if args.files and b'fscheck ls cat hexdump' not in info: raise AssertionError('File command firmware required')
            mounted=command('mount',b'FAT mounted type=')
            match=re.search(rb'FAT mounted type=(\d+) sectors=(\d+)',mounted)
            if not match or int(match[1]) not in (1,2,3,4) or int(match[2])<64: raise AssertionError('Invalid FAT/card geometry')
            record['fat_type'],record['sectors']=map(int,match.groups());record['mount_verified']=True
            status=command('sdinfo',b' error=ok\r\n')
            if b' ready=1 ' not in status or b' writes=0 ' not in status: raise AssertionError('Card not ready or unexpected write count')
            if expected is not None:
                wanted=f'FILE PASS bytes={len(expected)} crc={crc16(expected):08x}\r\n'.encode()
                for _ in range(args.repeat): command(f"fscheck '{args.file}'",wanted,120)
                command('umount',b'FAT unmounted\r\n');command('mount',b'FAT mounted type=')
                command(f"fscheck '{args.file}'",wanted,120)
                record.update(file_verified=True,file=args.file,byte_count=len(expected),crc16=f'{crc16(expected):04x}')
                if args.files:
                    listed=command(f"ls '{args.file}'",f'f {len(expected)} '.encode())
                    command('ls',b'\r\n')
                    raw_cat(f"cat '{args.file}'")
                    rows=[]
                    for pos in range(0,min(256,len(expected)),16):
                        row=expected[pos:min(pos+16,256)]
                        left=' '.join(f'{byte:02x}' for byte in row[:8]).ljust(23)
                        right=' '.join(f'{byte:02x}' for byte in row[8:]).ljust(23)
                        ascii_text=''.join(chr(byte) if 32<=byte<127 else '.' for byte in row).ljust(16)
                        rows.append(f'{pos:08x}  {left}  {right}  |{ascii_text}|\r\n')
                    dumped=command(f"hexdump '{args.file}'",b'\r\n')
                    body=dumped.split(b'\r\n',1)[1][:-len(prompt)]
                    if body!=''.join(rows).encode('ascii'): raise AssertionError('Hexdump rows mismatch')
                    record.update(file_commands_verified=True,raw_cat_verified=True,hexdump_bytes=min(256,len(expected)))
            memory=command('mem',b' bram=65536 ddr=134217728\r\n')
            match=re.search(rb'heap_free=(\d+) heap_min=(\d+)',memory)
            if not match or min(map(int,match.groups()))<4096: raise AssertionError('Insufficient heap')
            record['heap_free'],record['heap_min']=map(int,match.groups())
            states=command('tasks',b'name priority state stack_free_words\r\n')
            rows=[re.fullmatch(rb'(input|heartbeat|uart-tty|vga-tty|IDLE) (\d+) (\d+) (\d+)',row) for row in states.split(b'\r\n')]
            rows=[row.groups() for row in rows if row]
            if len(rows)!=5 or min(int(row[3]) for row in rows)<32: raise AssertionError('Task/stack acceptance failed')
            samples=[]
            for _ in range(2):
                text=command('uptime',b' input_dropped=')
                match=re.search(rb'ticks=(\d+) heartbeat=(\d+) io_polls=(\d+) input_dropped=(\d+)',text)
                if not match or int(match[4]): raise AssertionError('Scheduler/input acceptance failed')
                samples.append(tuple(map(int,match.groups())));time.sleep(.1)
            if any(samples[1][i]<=samples[0][i] for i in range(3)): raise AssertionError('Scheduler stopped')
            record['scheduler_samples']=samples
            command('umount',b'FAT unmounted\r\n')
        print('PTROCOS STORAGE HARDWARE PASS',flush=True)
    except Exception as error:
        record['failure']=str(error);raise
    finally:
        record['finished_utc']=datetime.now(timezone.utc).isoformat()
        (args.output/'result.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__': main()
