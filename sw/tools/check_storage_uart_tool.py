"""Verify the board acceptance tool's binary framing without claiming board I/O."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('storage_uart_tool',ROOT/'tools/ptrocos_storage_test.py')
tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
PROMPT=b'\r\x1b[2Kptroc> '

class Serial:
    def __init__(self,data,chunk,corrupt=False):
        self.data,self.chunk,self.corrupt=data,chunk,corrupt
        self.rx=bytearray();self.tx=bytearray();self.ticks=0
    def __enter__(self): return self
    def __exit__(self,*args): pass
    @property
    def in_waiting(self): return min(len(self.rx),self.chunk)
    def reset_input_buffer(self): self.rx.clear()
    def read(self,size):
        size=min(size,self.chunk);value=bytes(self.rx[:size]);del self.rx[:size];return value
    def write(self,part):
        if part==b'\x03': self.rx.extend(b'^C\r\n'+PROMPT);return 1
        self.tx.extend(part)
        if part!=b'\n': return 1
        text=self.tx[:-1].decode();self.tx.clear()
        if text=='uname': body=b'PtrocOS RV32IM\r\n'
        elif text=='help': body=b'mount umount sdinfo fscheck ls cat hexdump\r\n'
        elif text=='mount': body=b'FAT mounted type=4 sectors=32768\r\n'
        elif text=='umount': body=b'FAT unmounted\r\n'
        elif text=='sdinfo': body=b'SD ready=1 writes=0 error=ok\r\n'
        elif text.startswith('fscheck '): body=f'FILE PASS bytes={len(self.data)} crc={tool.crc16(self.data):08x}\r\n'.encode()
        elif text.startswith('cat '):
            body=self.data
            if self.corrupt: body=bytes([body[0]^1])+body[1:]
        elif text.startswith('hexdump '):
            rows=[]
            for pos in range(0,min(256,len(self.data)),16):
                row=self.data[pos:min(pos+16,256)]
                ascii_text=''.join(chr(b) if 32<=b<127 else '.' for b in row).ljust(16)
                rows.append(f'{pos:08x}  {row[:8].hex(" ").ljust(23)}  {row[8:].hex(" ").ljust(23)}  |{ascii_text}|\r\n')
            body=''.join(rows).encode()
        elif text.startswith('ls'): body=f'f {len(self.data)} HELLO.TXT\r\n'.encode()
        elif text=='mem': body=b'heap_free=8064 heap_min=7968 bram=65536 ddr=134217728\r\n'
        elif text=='tasks':
            body=b'name priority state stack_free_words\r\n'
            body+=b''.join(name+b' 2 1 100\r\n' for name in (b'input',b'heartbeat',b'uart-tty',b'vga-tty',b'IDLE'))
        elif text=='uptime':
            self.ticks+=10;body=f'ticks={self.ticks} heartbeat={self.ticks} io_polls={self.ticks} input_dropped=0\r\n'.encode()
        else: raise AssertionError(text)
        self.rx.extend(text.encode()+b'\r\n'+body+PROMPT);return 1

checks=0
with tempfile.TemporaryDirectory(prefix='ptrocos-uart-') as directory:
    folder=Path(directory);source=folder/'expected.bin'
    for data in (b'',b'no trailing newline',bytes(range(256))*4+PROMPT+b'\r\n\0\xff'+PROMPT):
        source.write_bytes(data)
        for chunk in (1,7,19,8192):
            output=folder/f'case{checks}';serial=Serial(data,chunk)
            argv=['ptrocos_storage_test.py','--port','FAKE','--file','/HELLO.TXT','--expected',str(source),
                  '--repeat','1','--files','--output',str(output)]
            with patch.object(sys,'argv',argv),patch.object(tool.serial,'Serial',return_value=serial),patch.object(tool.time,'sleep'),contextlib.redirect_stdout(io.StringIO()):
                tool.main()
            result=json.loads((output/'result.json').read_text(encoding='utf-8'))
            assert result['raw_cat_verified'] and result['file_commands_verified'] and not result['writes_performed']
            checks+=1
    source.write_bytes(b'wrong byte must fail')
    output=folder/'corrupt';serial=Serial(source.read_bytes(),7,True)
    argv=['ptrocos_storage_test.py','--port','FAKE','--file','/HELLO.TXT','--expected',str(source),
          '--repeat','1','--files','--output',str(output)]
    with patch.object(sys,'argv',argv),patch.object(tool.serial,'Serial',return_value=serial),patch.object(tool.time,'sleep'),contextlib.redirect_stdout(io.StringIO()):
        try: tool.main()
        except AssertionError as e: assert str(e)=='Raw cat bytes/prompt mismatch'
        else: raise AssertionError('Corrupt cat accepted')
    assert 'failure' in json.loads((output/'result.json').read_text(encoding='utf-8'));checks+=1
print(f'STORAGE UART TOOL FRAMING PASS checks={checks} empty binary prompt-in-file arbitrary-chunks corrupt-byte-rejected no-hardware')
