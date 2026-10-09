"""Real C player against independently clocked bounded sinks and byte fixtures."""
import ctypes as C
import json
from pathlib import Path
import random
import re
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/ptrocos_video';OUT.mkdir(parents=True,exist_ok=True)
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared','-DPTROCOS_VIDEO',
    '-I'+str(ROOT/'sw/tools/storage_native'),'-I'+str(ROOT/'sw/ptrocos'),
    *[str(ROOT/p) for p in ['sw/ptrocos/media/video_decode.c','sw/ptrocos/media/video_player.c','sw/tools/video_player_native.c']],
    '-o',str(OUT/'video_player.dll')],check=True)
lib=C.CDLL(str(OUT/'video_player.dll'))
READ=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint)
CANCEL=C.CFUNCTYPE(C.c_int,C.c_void_p)
WRITE=C.CFUNCTYPE(None,C.c_void_p,C.c_char_p)
HOOK=C.CFUNCTYPE(None,C.c_uint,C.c_uint,C.c_void_p)
class Source(C.Structure): _fields_=[('size',C.c_uint32),('read',READ),('cancel',CANCEL),('context',C.c_void_p)]
class Work(C.Structure): _fields_=[('input',C.c_uint8*2560),('output',C.c_uint32*320)]
lib.ptrocos_video_play.argtypes=[C.POINTER(Source),C.POINTER(Work),WRITE,C.c_void_p,C.POINTER(C.c_uint32)]
lib.video_native_hook.argtypes=[HOOK];lib.video_native_value.argtypes=[C.c_uint]
lib.video_native_close_error.argtypes=[C.c_int]
lib.video_native_frames.restype=C.POINTER(C.c_uint32);lib.video_native_ticks.restype=C.POINTER(C.c_uint32)
lib.video_native_samples.restype=C.POINTER(C.c_uint16)
checks=frames=samples=0;records=[]

def fixture(fps,count,rate):
    data=bytearray(struct.pack('<4sHHHHIIIII',b'PTV1',32,bool(rate),160,120,fps,count,rate,2400,0));bitmaps=[];sound=[]
    for frame in range(count):
        bits=bytes((index*3+frame*71)&255 for index in range(2400));bitmaps.append(bits);data.extend(bits)
        pcm=[((n*1009)^0x9876)&65535 for n in range(frame*rate//fps,(frame+1)*rate//fps)]
        sound.extend(pcm);data.extend(struct.pack('<'+'H'*len(pcm),*pcm))
    return bytes(data),bitmaps,sound

def run(fps,count,rate,delay=0,cancel_event=None,io_at=None,start=0xffffff00,expected=0,close_error=0):
    global checks,frames,samples
    data,bitmaps,sound=fixture(fps,count,rate);errors=[];output=bytearray();reads=0;closed=0
    cancel=C.c_uint32(0);lib.video_native_reset(start);lib.video_native_close_error(close_error)
    @READ
    def read(_,offset,destination,count):
        nonlocal reads
        try:
            reads+=1;assert offset+count<=len(data)
            if io_at==reads: return 2
            if delay and offset>=32: lib.video_native_advance(delay)
            C.memmove(destination,data[offset:offset+count],count);return 0
        except Exception as error: errors.append(repr(error));return 2
    @CANCEL
    def cancelled(_): return cancel.value
    @WRITE
    def write(_,text): output.extend(text)
    @HOOK
    def hook(event,index,pointer):
        nonlocal closed
        try:
            if event in [0,1]: assert C.string_at(pointer,2400)==bitmaps[index]
            if event==1: assert lib.video_native_value(8)==1
            if event==5:
                assert lib.video_native_value(8)==0 and lib.video_native_value(2)==1
                closed+=1
            if event==3: assert C.cast(pointer,C.POINTER(C.c_uint16))[0]==sound[index-1]
            if event==4: errors.append('unexpected underrun')
            if cancel_event==(event,index): cancel.value=1
        except Exception as error: errors.append(repr(error))
    lib.video_native_hook(hook);source=Source(len(data),read,cancelled,None)
    result=lib.ptrocos_video_play(C.byref(source),C.byref(Work()),write,None,C.byref(cancel))
    assert result==expected,(result,expected,output,errors)
    assert not errors,errors
    assert all(lib.video_native_value(index)==0 for index in (2,3,7,8))
    assert closed==(0 if io_at==1 else 1)
    shown=lib.video_native_value(0);played=lib.video_native_value(1)
    indices=[lib.video_native_frames()[i] for i in range(shown)]
    assert all(a<b for a,b in zip(indices,indices[1:])),indices
    if not result:
        assert indices[0]==0 and indices[-1]==count-1 and played==len(sound)
        match=re.search(rb'PTV played fps=(\d+) frames=(\d+) read=(\d+) displayed=(\d+) dropped=(\d+) elapsed_ms=(\d+) max_late_ms=(\d+) audio_rate=(\d+) playing=(\d+)',output)
        assert match,output
        values=list(map(int,match.groups()));assert values[:3]==[fps,count,count] and values[3]==shown
        assert values[4]==count-shown and values[-1]==0
        assert values[5]>=count*1000//fps
        assert all(lib.video_native_samples()[i]==value for i,value in enumerate(sound))
        records.append({'fps':fps,'frames':count,'rate':rate,'delay_ms_per_read':delay,'displayed':shown,'dropped':count-shown,'elapsed_ms':values[5]})
        frames+=count;samples+=played
    else:
        assert b'PTV played' not in output
    checks+=1

for fps in [10,15,30]:
    for rate in [0,8000,11025,16000]:
        for count in [1,4,31,90]: run(fps,count,rate)
run(30,90,0,delay=75) # Deliberately slower than the frame clock.
assert records[-1]['dropped']>0
for event,index in [(0,0),(0,3),(1,0),(1,2),(3,32)]:
    run(15,31,8000,cancel_event=(event,index),expected=3)
    run(15,4,8000)
for io_at in [1,2,3,7,15]:
    run(15,31,8000,io_at=io_at,expected=2)
    run(15,4,8000)
run(15,4,8000,close_error=2,expected=4)
run(15,4,8000,cancel_event=(1,0),close_error=2,expected=3)
(OUT/'native-player-results.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
print(f'PTV PLAYER PASS checks={checks} frames={frames} samples={samples} ring-bounds sample-clock silent-clock dropped cancel retry IO tick-wrap text-restored',flush=True)
