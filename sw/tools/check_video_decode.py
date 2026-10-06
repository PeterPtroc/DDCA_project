"""Independent PTV1 bytes, PCM and rational-clock checks against the real C."""
import ctypes as C
from pathlib import Path
import random
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/ptrocos_video';OUT.mkdir(parents=True,exist_ok=True)
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
    str(ROOT/'sw/ptrocos/media/video_decode.c'),'-o',str(OUT/'video_decode.dll')],check=True)
lib=C.CDLL(str(OUT/'video_decode.dll'))
READ=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint)
CANCEL=C.CFUNCTYPE(C.c_int,C.c_void_p)
BITMAP=C.CFUNCTYPE(C.c_int,C.c_void_p,C.POINTER(C.c_uint8))
PCM=C.CFUNCTYPE(C.c_int,C.c_void_p,C.POINTER(C.c_uint16),C.c_uint)
class Source(C.Structure): _fields_=[('size',C.c_uint32),('read',READ),('cancel',CANCEL),('context',C.c_void_p)]
class Video(C.Structure): _fields_=[('fps',C.c_uint32),('frames',C.c_uint32),('rate',C.c_uint32)]
class Work(C.Structure): _fields_=[('input',C.c_uint8*2560),('output',C.c_uint32*320)]
lib.media_video_open.argtypes=[C.POINTER(Source),C.POINTER(Video)]
lib.media_video_audio_count.argtypes=[C.POINTER(Video),C.c_uint32];lib.media_video_audio_count.restype=C.c_uint
lib.media_video_due.argtypes=[C.POINTER(Video),C.c_uint32];lib.media_video_due.restype=C.c_uint32
lib.media_video_frame.argtypes=[C.POINTER(Source),C.POINTER(Video),C.c_uint32,C.POINTER(Work),BITMAP,PCM,C.c_void_p]
checks=frames=samples=0;rng=random.Random(0x7076)

def fixture(fps,count,rate):
    data=bytearray(struct.pack('<4sHHHHIIIII',b'PTV1',32,bool(rate),160,120,fps,count,rate,2400,0))
    bitmaps=[];sound=[]
    for frame in range(count):
        bits=bytes(((index*17+frame*71)^(index>>3))&255 for index in range(2400));bitmaps.append(bits)
        pcm=[((n*1009)^0x9876)&65535 for n in range(frame*rate//fps,(frame+1)*rate//fps)]
        sound.append(pcm);data.extend(bits);data.extend(struct.pack('<'+'H'*len(pcm),*pcm))
    return bytes(data),bitmaps,sound

def exercise(data,expected=0,bitmaps=None,sound=None,cancel_at=None,io_at=None,sink=0):
    global checks,frames,samples
    reads=[];cancel_calls=0;emitted=0;audio=[];callback_errors=[]
    @READ
    def read(_,offset,destination,count):
        try:
            assert count<=2560 and offset+count<=len(data)
            reads.append((offset,count))
            if io_at==len(reads): return 2
            C.memmove(destination,data[offset:offset+count],count);return 0
        except Exception as error: callback_errors.append(error);return 2
    @CANCEL
    def cancel(_):
        nonlocal cancel_calls
        cancel_calls+=1;return cancel_at is not None and cancel_calls>=cancel_at
    @BITMAP
    def bitmap(_,values):
        nonlocal emitted
        try:
            assert C.string_at(values,2400)==bitmaps[emitted]
            emitted+=1;return 4 if sink==1 else 0
        except Exception as error: callback_errors.append(error);return 4
    @PCM
    def pcm(_,values,count):
        try:
            audio.extend(values[i] for i in range(count));return 4 if sink==2 else 0
        except Exception as error: callback_errors.append(error);return 4
    source=Source(len(data),read,cancel,None);v=Video();work=Work()
    result=lib.media_video_open(C.byref(source),C.byref(v))
    if bitmaps is not None and not result:
        for frame in range(v.frames):
            assert lib.media_video_audio_count(C.byref(v),frame)==len(sound[frame])
            result=lib.media_video_frame(C.byref(source),C.byref(v),frame,C.byref(work),bitmap,pcm,None)
            if result: break
        if not result:
            assert emitted==len(bitmaps) and audio==[value for packet in sound for value in packet]
            assert all(offset==sum(c for _,c in reads[:i]) for i,(offset,count) in enumerate(reads))
            assert lib.media_video_frame(C.byref(source),C.byref(v),v.frames,C.byref(work),bitmap,pcm,None)==1
            for units in [0,1,31,32,999,1000,9999,0xffffffff]+[rng.getrandbits(32) for _ in range(100)]:
                wanted=min(v.frames-1,units*v.fps//(v.rate or 1000))
                assert lib.media_video_due(C.byref(v),units)==wanted
            frames+=emitted;samples+=len(audio)
    assert not callback_errors,callback_errors
    assert result==expected,(result,expected,len(data),cancel_at,io_at,sink)
    checks+=1

for fps in [10,15,30]:
    for rate in [0,8000,11025,16000]:
        for count in [1,4,31]:
            data,bits,pcm=fixture(fps,count,rate)
            exercise(data,bitmaps=bits,sound=pcm)
            exercise(data,3,bits,pcm,cancel_at=1)
            exercise(data,3,bits,pcm,cancel_at=2)
            exercise(data,2,bits,pcm,io_at=1)
            exercise(data,2,bits,pcm,io_at=2)
            exercise(data,4,bits,pcm,sink=1)
            if rate:
                exercise(data,4,bits,pcm,sink=2)
                exercise(data,2,bits,pcm,io_at=3)
            for length in [0,1,31,32,len(data)-1]: exercise(data[:length],1)
data,bits,pcm=fixture(15,1,8000)
for length in range(len(data)): exercise(data[:length],1)
for offset,width,values in [(0,4,[0,0x31565451]),(4,2,[0,31,33,65535]),(6,2,[0,2,65535]),
        (8,2,[0,159,161,65535]),(10,2,[0,119,121,65535]),(12,4,[0,9,31,0xffffffff]),
        (16,4,[0,54001,0xffffffff]),(20,4,[0,7999,16001,0xffffffff]),(24,4,[0,2399,2401,0xffffffff]),(28,4,[1,0xffffffff])]:
    for value in values:
        broken=bytearray(data);broken[offset:offset+width]=value.to_bytes(width,'little');exercise(bytes(broken),1)
exercise(data+b'\0',1)
for _ in range(1000):
    broken=rng.randbytes(32)+data[32:];exercise(broken,1)
print(f'PTV DECODE PASS checks={checks} frames={frames} samples={samples} rational-clock bounds cancel IO sink',flush=True)
