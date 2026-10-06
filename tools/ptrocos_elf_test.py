"""Board UART acceptance for ELF loading/execution without a physical SD card."""
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import re
import time
import serial
PROMPT=b'\r\x1b[2Kptroc> '

def main():
    p=argparse.ArgumentParser();p.add_argument('--port',required=True)
    p.add_argument('--output',type=Path,default=Path('build/ptrocos_elf_hardware'));a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True)
    record={'port':a.port,'started_utc':datetime.now(timezone.utc).isoformat(),'checks':[],
            'elf_uart_verified':False,'real_sd_elf_execution_verified':False,
            'keyboard_physical_verified':False,'visual_display_verified':False}
    try:
        with serial.Serial(a.port,115200,timeout=.02,write_timeout=3) as port,(a.output/'uart.log').open('wb') as log:
            def send(data):
                for value in data:port.write(bytes([value]));time.sleep(.003)
            def until(predicate,timeout=15):
                data=bytearray();end=time.monotonic()+timeout
                while time.monotonic()<end:
                    packet=port.read(max(1,port.in_waiting));data.extend(packet);log.write(packet);log.flush()
                    if b'PTROCOS PANIC' in data:raise AssertionError('Firmware panic')
                    # Preserve raw capture, but tolerate repeated CR in line
                    # endings when matching complete lines and the prompt.
                    normalized=re.sub(rb'\r+\n',b'\r\n',bytes(data))
                    if predicate(normalized):return normalized
                raise TimeoutError(bytes(data))
            def command(text,expected):
                send(text.encode()+b'\r');choices=expected if isinstance(expected,tuple) else (expected,)
                return until(lambda data:data.endswith(PROMPT) and any(word in data for word in choices))
            def mark(name):record['checks'].append(name);print('PASS '+name,flush=True)
            port.reset_input_buffer();send(b'\x03');until(lambda data:b'^C\r\n' in data and data.endswith(PROMPT))
            info=command('elf info',b'ELF32 RV32IM ILP32 ABI=1');assert b'code=0x00010000' in info
            command('run',b'usage: run <path>');command('elf invalid',b'usage: run <path>')
            command('run /HELLO.ELF',b'mount the SD card first')
            help_text=command('help',b'Ctrl+C cancels');assert b'elf run' in help_text
            mark('ELF ABI commands and unmounted guard')
            for i in range(3):
                response=command('elf test',b'ELF TEST PASS')
                assert response.count(b'ELF HELLO BSS PASS')==2 and response.count(b'ELF returned code=37')==2,response
                assert b'ELF fault cause=2 pc=' in response and b'ELF timeout\r\n' in response,response
                command('ddrtest',b'DDR DMA PASS words=256 crc=0000f364')
                mark(f'compiled Hello reload-BSS illegal instruction timeout shell recovery DMA {i+1}')
            # The diagnostic loop has a short deadline. Cancelling during the
            # preceding Hello/DDR load still proves lock and runtime cleanup.
            send(b'elf test\r');until(lambda data:b'ELF HELLO BSS PASS\r\n' in data)
            send(b'\x03');until(lambda data:b'^C cancelled\r\n' in data and data.endswith(PROMPT))
            command('elf test',b'ELF TEST PASS');mark('ELF cancellation and retry')
            response=command('uptime',b'input_dropped=')
            m=re.search(rb'ticks=(\d+) heartbeat=(\d+) io_polls=(\d+) input_dropped=(\d+)',response)
            assert m and min(map(int,m.groups()[:3]))>0 and int(m[4])==0,response
            record['uptime']=dict(zip(('ticks','heartbeat','io_polls','input_dropped'),map(int,m.groups())))
            command('tasks',b'name priority state stack_free_words')
            command('audio test',b'AUDIO PASS rate=8000 samples=256 underruns=0')
            command('video test',b'PTV played fps=')
            command('gfx off',b'gfx text mode');mark('scheduler and prior audio/video diagnostics responsive')
            response=command('mount',(b'SD=',b'FAT mounted'))
            record['real_sd_mount_response']=response.decode('ascii',errors='replace')
            record['real_sd_mounted']=b'FAT mounted' in response;mark('real SD mount result recorded')
            record['elf_uart_verified']=True
        print('PTROCOS ELF HARDWARE UART PASS',flush=True)
    except Exception as error:record['failure']=repr(error);raise
    finally:
        record['finished_utc']=datetime.now(timezone.utc).isoformat()
        (a.output/'result.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
