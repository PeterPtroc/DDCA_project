"""Independent BMP/WAV byte and pixel/sample oracles for the real C decoder."""
import ctypes as C
from pathlib import Path
import random
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/ptrocos_media';OUT.mkdir(parents=True,exist_ok=True)
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
    str(ROOT/'sw/ptrocos/media/decode.c'),'-o',str(OUT/'decode.dll')],check=True)
lib=C.CDLL(str(OUT/'decode.dll'))
READ=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint)
CANCEL=C.CFUNCTYPE(C.c_int,C.c_void_p)
ROW=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_uint,C.POINTER(C.c_uint32))
SAMPLES=C.CFUNCTYPE(C.c_int,C.c_void_p,C.POINTER(C.c_uint16),C.c_uint)
class Source(C.Structure): _fields_=[('size',C.c_uint32),('read',READ),('cancel',CANCEL),('context',C.c_void_p)]
class BMP(C.Structure): _fields_=[(x,C.c_uint32) for x in ('width','height','offset','stride','bits','top_down')]
class WAV(C.Structure): _fields_=[(x,C.c_uint32) for x in ('rate','offset','bytes','frames','channels','bits','align')]
class Work(C.Structure): _fields_=[('input',C.c_uint8*2560),('output',C.c_uint32*320)]
lib.media_bmp_open.argtypes=[C.POINTER(Source),C.POINTER(BMP)]
lib.media_bmp_draw.argtypes=[C.POINTER(Source),C.POINTER(BMP),C.POINTER(Work),ROW,C.c_void_p]
lib.media_wav_open.argtypes=[C.POINTER(Source),C.POINTER(WAV)]
lib.media_wav_play.argtypes=[C.POINTER(Source),C.POINTER(WAV),C.POINTER(Work),SAMPLES,C.c_void_p]
checks=pixels=samples=0
rng=random.Random(0xb09)

from media_fixture import bmp,wav,chunk

def run(data,kind='bmp',cancel_at=None,io_at=None,sink_error=False,decode=True):
    global checks,pixels,samples
    read_count=0;emitted=[];exceptions=[];cancelled=False
    def read(ctx,offset,buffer,count):
        nonlocal read_count,cancelled
        try:
            assert offset+count<=len(data),'out-of-bounds read'
            read_count+=1
            if io_at==read_count:return 2
            C.memmove(buffer,bytes(data[offset:offset+count]),count)
            if cancel_at==read_count:cancelled=True
            return 0
        except Exception as e:exceptions.append(e);return 2
    read_cb=READ(read);cancel_cb=CANCEL(lambda ctx:int(cancelled))
    source=Source(len(data),read_cb,cancel_cb,None);header=BMP() if kind=='bmp' else WAV();work=Work()
    result=getattr(lib,'media_'+kind+'_open')(C.byref(source),C.byref(header))
    def row(ctx,y,values):
        emitted.append((y,[v for word in values[:320] for v in (word&65535,word>>16)]))
        return 4 if sink_error else 0
    def pcm(ctx,values,count):emitted.extend(values[:count]);return 4 if sink_error else 0
    row_cb=ROW(row);pcm_cb=SAMPLES(pcm)
    if result==0 and decode:
        result=(lib.media_bmp_draw(C.byref(source),C.byref(header),C.byref(work),row_cb,None) if kind=='bmp'
            else lib.media_wav_play(C.byref(source),C.byref(header),C.byref(work),pcm_cb,None))
    if exceptions:raise exceptions[0]
    checks+=1
    if kind=='bmp':pixels+=len(emitted)*640
    else:samples+=len(emitted)
    if kind=='bmp':emitted=[row for _,row in sorted(emitted)]
    return result,emitted,header

for width,height in [(1,1),(3,5),(639,4),(640,480),(317,239)]:
    for bits in (24,32):
        for top in (False,True):
            data,expected=bmp(width,height,bits,top,108 if top else 40)
            result,actual,header=run(data);assert result==0 and actual==expected
for bits in (8,16):
    for channels in (1,2):
        for rate in (8000,11025,22050,44100,48000):
            for first in (False,True):
                data,expected=wav(rate=rate,bits=bits,channels=channels,data_first=first)
                result,actual,header=run(data,'wav');assert result==0 and actual==expected

valid_bmp,_=bmp(7,3);valid_wav,_=wav()
for kind,data in [('bmp',valid_bmp),('wav',valid_wav)]:
    for end in range(len(data)):
        # Every truncation of declared content must fail, including partial chunks.
        assert run(data[:end],kind,decode=False)[0]==1,(kind,end)
    for io in (1,2):assert run(data,kind,io_at=io)[0]==2
    for cancel in (1,2):assert run(data,kind,cancel_at=cancel)[0]==3
    assert run(data,kind,sink_error=True)[0]==4

for offset,value in [(2,0),(10,53),(14,39),(18,0),(18,641),(18,0x80000000),(22,0),(22,481),
                     (22,0x80000000),(30,1),(30,3),(34,1),(34,0xffffffff)]:
    bad=bytearray(valid_bmp);struct.pack_into('<I',bad,offset,value)
    assert run(bad,decode=False)[0]==1,('bmp',offset,value)
for kind,data in [('bmp',valid_bmp),('wav',valid_wav)]:
    for _ in range(1000):
        bad=bytearray(data)
        for _ in range(rng.randrange(1,5)):bad[rng.randrange(min(len(bad),64))]=rng.randrange(256)
        result,_,_=run(bad,kind,decode=False);assert result in (0,1)
fmt_offset=valid_wav.index(b'fmt ')+8
for offset,form,value in [(0,'H',3),(2,'H',0),(2,'H',3),(4,'I',7999),(4,'I',48001),
                           (8,'I',1),(12,'H',1),(14,'H',24)]:
    bad=bytearray(valid_wav);struct.pack_into('<'+form,bad,fmt_offset+offset,value)
    assert run(bad,'wav',decode=False)[0]==1
for body in [chunk(b'fmt ',valid_wav[fmt_offset:fmt_offset+16])*2+chunk(b'data',b'12'),
             chunk(b'fmt ',valid_wav[fmt_offset:fmt_offset+16])+chunk(b'data',b'1234')*2,
             chunk(b'fmt ',valid_wav[fmt_offset:fmt_offset+16])+chunk(b'data',b'1'),
             chunk(b'data',b'12'),b'JUNK'+struct.pack('<I',0xffffffff)]:
    data=b'RIFF'+struct.pack('<I',len(body)+4)+b'WAVE'+body
    assert run(data,'wav',decode=False)[0]==1
print(f'MEDIA DECODE PASS checks={checks} pixels={pixels} samples={samples}')
