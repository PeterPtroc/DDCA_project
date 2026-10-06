"""UART acceptance of timed monochrome video and PCM without an SD card."""
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import re
import time
import serial

PROMPT=b'\r\x1b[2Kptroc> '
FIELDS=('fps','frames','read','displayed','dropped','elapsed_ms','max_late_ms','audio_rate','playing')
INFO=re.compile(rb'(?:PTV played|video) fps=(\d+) frames=(\d+) read=(\d+) displayed=(\d+) dropped=(\d+) elapsed_ms=(\d+) max_late_ms=(\d+) audio_rate=(\d+) playing=(\d+)')
def main():
    p=argparse.ArgumentParser();p.add_argument('--port',required=True)
    p.add_argument('--output',type=Path,default=Path('build/ptrocos_video_hardware'));a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True)
    result={'port':a.port,'started_utc':datetime.now(timezone.utc).isoformat(),'checks':[],
        'trials':[],'uart_video_verified':False,'real_sd_video_verified':False,
        'badapple_board_playback_verified':False,'visual_display_verified':False,
        'analog_audio_verified':False,'keyboard_physical_verified':False}
    try:
        with serial.Serial(a.port,115200,timeout=.02,write_timeout=3) as port,(a.output/'uart.log').open('wb') as log:
            def send(data):
                for value in data:port.write(bytes([value]));time.sleep(.003)
            def until(predicate,timeout=15):
                data=bytearray();start=time.monotonic()
                while time.monotonic()-start<timeout:
                    packet=port.read(max(1,port.in_waiting));data.extend(packet);log.write(packet);log.flush()
                    if b'PTROCOS PANIC' in data:raise AssertionError('Firmware panic')
                    if predicate(bytes(data)):return bytes(data)
                raise TimeoutError(bytes(data))
            def command(text,expected):
                send(text.encode()+b'\r');choices=expected if isinstance(expected,tuple) else (expected,)
                return until(lambda data:data.endswith(PROMPT) and any(word in data for word in choices))
            def mark(name):result['checks'].append(name);print('PASS '+name,flush=True)
            def video_info():
                response=command('video info',b'video fps=');match=INFO.search(response)
                assert match,response;return dict(zip(FIELDS,map(int,match.groups())))
            def graphics():
                response=command('gfx info',b'gfx 640x480')
                match=re.search(rb'status=(\d+) front=(\d+).*underruns=(\d+).*errors=(\d+)',response)
                assert match and int(match[3])==int(match[4])==0,response
                return dict(zip(('status','front','underruns','errors'),map(int,match.groups())))
            port.reset_input_buffer();send(b'\x03');until(lambda data:b'^C\r\n' in data and data.endswith(PROMPT))
            initial=video_info();assert initial['frames']==initial['playing']==0
            help_text=command('help',b'Ctrl+C cancels');assert b'play' in help_text
            command('play',b'usage: play <path>');command('video invalid',b'usage: video info | test')
            command('play /BADAPPLE.PTV',b'mount the SD card first');mark('video commands and unmounted guards')
            for trial in range(3):
                output=command('video test',b'PTV played fps=');match=INFO.search(output);assert match,output
                values=dict(zip(FIELDS,map(int,match.groups())));result['trials'].append(values)
                assert values['fps']==15 and values['frames']==values['read']==4 and values['audio_rate']==8000
                assert values['displayed']+values['dropped']==4 and not values['dropped'] and not values['playing'],values
                assert 266<=values['elapsed_ms']<400 and values['max_late_ms']<=40,values
                audio=command('audio info',b'audio rate=')
                assert b'status=4 queued=0 played=2133 underruns=0' in audio,audio
                state=graphics();assert state['status']==1 and 0x81200000<=state['front']<0x81208000,state
                command('ddrtest',b'DDR DMA PASS words=256 crc=0000f364')
                mark(f'timed four-frame video and 2133 PCM samples with DDR DMA {trial+1}')
            send(b'video test\r');until(lambda data:b'PTV fps=' in data and b'Ctrl+C cancels\r\n' in data)
            time.sleep(.03);send(b'\x03');until(lambda data:b'^C cancelled\r\n' in data and data.endswith(PROMPT))
            state=video_info();assert state['playing']==0
            audio=command('audio info',b'audio rate=');assert b'status=0 queued=0 played=0 underruns=0' in audio,audio
            mark('video cancellation stops audio and releases playback state')
            command('video test',b'PTV played fps=');assert video_info()['displayed']==4
            mark('video retry after cancellation')
            command('gfx pattern 0',b'gfx pattern=0 displayed');graphics()
            command('video test',b'PTV played fps=');assert video_info()['displayed']==4;graphics()
            mark('RGB565 and monochrome formats switch in both directions')
            command('audio test',b'AUDIO PASS rate=8000 samples=256 underruns=0')
            command('gfx off',b'gfx text mode');assert graphics()['status']==0
            response=command('uptime',b'input_dropped=')
            match=re.search(rb'ticks=(\d+) heartbeat=(\d+) io_polls=(\d+) input_dropped=(\d+)',response)
            assert match and min(map(int,match.groups()[:3]))>0 and int(match[4])==0,response
            result['uptime']=dict(zip(('ticks','heartbeat','io_polls','input_dropped'),map(int,match.groups())))
            command('tasks',b'name priority state stack_free_words');mark('scheduler UART and prior audio diagnostic responsive; text restored')
            response=command('mount',(b'SD=',b'FAT mounted'));result['real_sd_mount_response']=response.decode('ascii',errors='replace')
            result['real_sd_mounted']=b'FAT mounted' in response
            mark('real SD mount result recorded');result['uart_video_verified']=True
        print('PTROCOS VIDEO HARDWARE UART PASS',flush=True)
    except Exception as error:
        result['failure']=repr(error);raise
    finally:
        result['finished_utc']=datetime.now(timezone.utc).isoformat()
        (a.output/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
