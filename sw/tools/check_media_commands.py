"""Real media commands -> FatFs -> diskio -> SD; native pixel/audio sinks."""
import ctypes as C
import os
from pathlib import Path
import shutil
import struct
import subprocess
from check_sd_card import Model,Transport,TRANSFER,ROOT
from media_fixture import MediaImage
from fatfs_fixture import Image
OUT=ROOT/'build/ptrocos_media';OUT.mkdir(parents=True,exist_ok=True)
sources=['sw/ptrocos/storage/sd_card.c','sw/ptrocos/storage/storage_disk.c',
    'sw/ptrocos/storage/storage_commands.c','sw/ptrocos/shell.c',
    'sw/ptrocos/media/decode.c','sw/ptrocos/media/media_commands.c',
    'third_party/fatfs/ff.c','third_party/fatfs/ffunicode.c',
    'sw/tools/fatfs_native.c','sw/tools/storage_commands_native.c','sw/tools/media_commands_native.c']
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
    '-DPTROCOS_STORAGE','-DPTROCOS_GRAPHICS','-DPTROCOS_MEDIA',
    '-I'+str(ROOT/'sw/tools/storage_native'),'-I'+str(ROOT/'sw/ptrocos'),
    '-I'+str(ROOT/'sw/ptrocos/storage'),'-I'+str(ROOT/'third_party/fatfs'),
    *[str(ROOT/s) for s in sources],'-o',str(OUT/'media_commands.dll'),'-lwinpthread'],check=True)
dll_directory=os.add_dll_directory(str(Path(shutil.which('gcc.exe')).parent))
lib=C.CDLL(str(OUT/'media_commands.dll'))
WRITE=C.CFUNCTYPE(None,C.c_void_p,C.c_void_p);BYTE=C.CFUNCTYPE(None,C.c_void_p,C.c_uint8)
HOOK=C.CFUNCTYPE(None,C.c_uint,C.c_uint)
lib.storage_native_setup.argtypes=[C.POINTER(Transport)];lib.storage_native_transfer.argtypes=[TRANSFER]
lib.ptrocos_storage_command.argtypes=[C.c_uint,C.POINTER(C.c_char_p),WRITE,BYTE,C.c_void_p,C.POINTER(C.c_uint32)]
lib.media_native_hook.argtypes=[HOOK];lib.media_native_count.argtypes=[C.c_uint]
lib.media_native_pixels.restype=C.c_void_p;lib.media_native_samples.restype=C.c_void_p
checks=0
def command(model,*args,cancel_sink=None,cancel_io=None):
    global checks
    output=bytearray();cancel=C.c_uint32()
    def put(ctx,ptr):output.extend(C.string_at(ptr))
    def hook(stage,value):
        if cancel_sink is not None and (stage,value)>=cancel_sink:cancel.value=1
    write=WRITE(put);byte=BYTE(lambda ctx,ch:output.append(ch));callback=HOOK(hook)
    lib.media_native_hook(callback)
    original=model.bus.transfer;transfer=original
    if cancel_io is not None:
        target=model.transfers+cancel_io
        def io(ctx,value):
            if model.transfers>=target:cancel.value=1
            return original(ctx,value)
        transfer=TRANSFER(io);lib.storage_native_transfer(transfer)
    argv=(C.c_char_p*len(args))(*(a.encode() for a in args))
    result=lib.ptrocos_storage_command(len(args),argv,write,byte,None,C.byref(cancel))
    lib.storage_native_transfer(original)
    if model.exception:raise model.exception
    assert result==1;checks+=1
    return bytes(output),cancel.value
def pixels(expected):
    raw=C.string_at(lib.media_native_pixels(),640*480*2)
    actual=struct.unpack('<307200H',raw);assert actual==tuple(v for row in expected for v in row)
def samples(expected):
    count=lib.media_native_count(2);assert count==len(expected)
    assert struct.unpack('<'+str(count)+'H',C.string_at(lib.media_native_samples(),count*2))==tuple(expected)

for kind,prefix,version,high in ((12,0,1,False),(16,0,2,True),(32,0,2,True),(16,2048,2,False),(64,0,2,True)):
    fixture=MediaImage(kind,prefix);model=Model(version,high);model.storage=dict(fixture.initial)
    if high:model.sectors=max(32768,((fixture.total+prefix+1023)//1024)*1024)
    lib.storage_native_setup(C.byref(model.bus));lib.media_native_reset()
    assert command(model,'umount')[0]==b'FAT unmounted\r\n'
    for name in ('bmp','wav'):assert command(model,name,'/MISSING')[0]==b'mount the SD card first\r\n'
    assert command(model,'mount')[0].startswith(b'FAT mounted')
    for path,expected in [('IMAGE.BMP',fixture.pixels),('TOP.BMP',fixture.top_pixels)]:
        assert command(model,'bmp','/'+path)[0].endswith(b'BMP displayed\r\n');pixels(expected)
    for path,expected in [('SOUND.WAV',fixture.samples),('SHORT.WAV',fixture.short_samples)]:
        assert command(model,'wav','/'+path)[0].endswith(f'WAV played frames={len(expected)}\r\n'.encode())
        samples(expected);assert lib.media_native_count(3)==1
    for name in ('bmp','wav'):
        before=lib.media_native_count(0)
        assert command(model,name,'/BAD.'+name.upper())[0]==b'unsupported or malformed media file\r\n'
        assert lib.media_native_count(0)==before
        assert command(model,name)[0]==b'usage: bmp <path> | wav <path>\r\n'
        assert command(model,name,'/MISSING')[0].startswith(b'FatFs error=4')
    before=C.string_at(lib.media_native_pixels(),614400)
    _,cancel=command(model,'bmp','/IMAGE.BMP',cancel_sink=(0,4));assert cancel
    assert C.string_at(lib.media_native_pixels(),614400)==before
    # Sink cancellation preserves mount. SD transaction cancellation invalidates it.
    assert command(model,'bmp','/TOP.BMP')[0].endswith(b'BMP displayed\r\n')
    _,cancel=command(model,'wav','/SOUND.WAV',cancel_sink=(1,512));assert cancel and not lib.media_native_count(3)
    assert command(model,'wav','/SHORT.WAV')[0].endswith(b'frames=537\r\n')
    _,cancel=command(model,'bmp','/IMAGE.BMP',cancel_io=200);assert cancel
    assert command(model,'wav','/SOUND.WAV')[0]==b'mount the SD card first\r\n'
    assert command(model,'mount')[0].startswith(b'FAT mounted')
    model.attached=False
    assert b'FatFs error=3' in command(model,'wav','/SOUND.WAV')[0]
    model.attached=True
    assert command(model,'mount')[0].startswith(b'FAT mounted')
    model.read_crc_bad=True
    assert b'FatFs error=' in command(model,'bmp','/IMAGE.BMP')[0]
    model.read_crc_bad=False
    assert command(model,'mount')[0].startswith(b'FAT mounted')
    assert command(model,'wav','/SHORT.WAV')[0].endswith(b'frames=537\r\n')
    assert command(model,'umount')[0]==b'FAT unmounted\r\n'
    print(f'MEDIA COMMAND FIXTURE PASS {"exFAT" if kind==64 else f"FAT{kind}"} prefix={prefix} fragmented pixels/PCM cancel removal CRC cleanup',flush=True)
fixture=Image(64,large=True);model=Model();model.sectors=fixture.total;model.storage=dict(fixture.initial)
lib.storage_native_setup(C.byref(model.bus));assert command(model,'mount')[0].startswith(b'FAT mounted type=4')
for name in ('bmp','wav'):
    before=lib.media_native_count(0)
    assert command(model,name,'/BIG.BIN')[0]==b'unsupported or malformed media file\r\n'
    assert lib.media_native_count(0)==before
assert command(model,'umount')[0]==b'FAT unmounted\r\n'
print(f'MEDIA COMMANDS NATIVE PASS checks={checks} oversized-exFAT-rejected')
