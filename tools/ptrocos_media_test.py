"""UART acceptance for audio FIFO and existing DDR graphics without external devices."""
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import re
import time
import serial
PROMPT=b'\r\x1b[2Kptroc> '
INFO=re.compile(rb'audio rate=(\d+) status=(\d+) queued=(\d+) played=(\d+) underruns=(\d+)')
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--port',required=True)
    parser.add_argument('--output',type=Path,default=Path('build/ptrocos_media_hardware'))
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    record={'port':args.port,'started_utc':datetime.now(timezone.utc).isoformat(),
        'audio_uart_verified':False,'analog_audio_verified':False,'sd_media_verified':False,
        'visual_display_verified':False,'keyboard_physical_verified':False,'checks':[],'samples':[]}
    try:
        with serial.Serial(args.port,115200,timeout=.02,write_timeout=3) as port,(args.output/'uart.log').open('wb') as log:
            def send(data):
                for value in data:port.write(bytes([value]));time.sleep(.003)
            def until(predicate,timeout=12):
                received=bytearray();deadline=time.monotonic()+timeout
                while time.monotonic()<deadline:
                    data=port.read(max(1,port.in_waiting));received.extend(data);log.write(data);log.flush()
                    if b'PTROCOS PANIC' in received:raise AssertionError('Firmware panic')
                    if predicate(bytes(received)):return bytes(received)
                raise TimeoutError(f'Media UART timeout: {bytes(received)!r}')
            def command(text,expected):
                send(text.encode()+b'\r')
                choices=expected if isinstance(expected,tuple) else (expected,)
                return until(lambda data:any(value in data for value in choices) and data.endswith(PROMPT))
            def mark(name):record['checks'].append(name);print('PASS '+name,flush=True)
            def audio():
                response=command('audio info',b'audio rate=');match=INFO.search(response)
                assert match,response
                value=dict(zip(('rate','status','queued','played','underruns'),map(int,match.groups())))
                record['samples'].append(value);return value
            port.reset_input_buffer();send(b'\x03');until(lambda data:b'^C\r\n' in data and data.endswith(PROMPT))
            initial=audio();assert initial['status']==0 and initial['played']==0 and initial['queued']==0
            mark('reset audio output disabled and FIFO empty')
            help_text=command('help',b'Ctrl+C cancels');assert b'bmp wav audio' in help_text
            mark('media commands available in shell')
            command('audio unknown',b'usage: audio info | test');command('bmp',b'usage: bmp <path> | wav <path>')
            command('wav',b'usage: bmp <path> | wav <path>');assert audio()==initial
            mark('invalid commands preserve audio state')
            for name in ('bmp','wav'):
                command(name+' /MISSING',b'mount the SD card first')
            mark('unmounted file guards')
            command('gfx pattern 0',b'gfx pattern=0 displayed')
            for trial in range(3):
                command('audio test',b'AUDIO PASS rate=8000 samples=256 underruns=0')
                value=audio();assert value=={'rate':8000,'status':4,'queued':0,'played':256,'underruns':0},value
                command('ddrtest',b'DDR DMA PASS words=256 crc=0000f364')
                info=command('gfx info',b'gfx 640x480 RGB565');match=re.search(rb'underruns=(\d+).*errors=(\d+)',info)
                assert match and int(match[1])==int(match[2])==0
                mark(f'audio exact completion with VGA scanout and DDR DMA {trial+1}')
            send(b'audio test\r');send(b'\x03')
            until(lambda data:b'^C cancelled\r\n' in data and data.endswith(PROMPT))
            value=audio();assert value['status']==value['queued']==value['played']==value['underruns']==0,value
            mark('Ctrl+C flushes audio and disables amplifier')
            command('audio test',b'AUDIO PASS rate=8000 samples=256 underruns=0');assert audio()['played']==256
            mark('audio retry after cancellation')
            response=command('uptime',b'input_dropped=');match=re.search(rb'ticks=(\d+) heartbeat=(\d+) io_polls=(\d+) input_dropped=(\d+)',response)
            assert match and int(match[4])==0 and min(map(int,match.groups()[:3]))>0
            record['uptime']=dict(zip(('ticks','heartbeat','io_polls','input_dropped'),map(int,match.groups())))
            command('tasks',b'name priority state stack_free_words');command('gfx off',b'gfx text mode')
            mark('scheduler and UART remain responsive; text mode restored')
            response=command('mount',(b'SD=',b'FAT mounted'))
            record['real_sd_mount_response']=response.decode('ascii',errors='replace')
            record['real_sd_mounted']=b'FAT mounted' in response
            mark('SD mount result recorded without firmware panic')
            record['audio_uart_verified']=True
        print('PTROCOS MEDIA HARDWARE UART PASS',flush=True)
    except Exception as error:
        record['failure']=repr(error);raise
    finally:
        record['finished_utc']=datetime.now(timezone.utc).isoformat()
        (args.output/'result.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
