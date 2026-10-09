"""PTV command -> real FatFs/diskio/SD with independently checked sinks."""
import ctypes as C
import os
from pathlib import Path
import shutil
import struct
import subprocess
from check_sd_card import Model,Transport,TRANSFER,ROOT
from video_fixture import VideoImage

OUT=ROOT/'build/ptrocos_video';OUT.mkdir(parents=True,exist_ok=True)
sources=['sw/ptrocos/storage/sd_card.c','sw/ptrocos/storage/storage_disk.c',
    'sw/ptrocos/storage/storage_commands.c','sw/ptrocos/shell.c',
    'sw/ptrocos/media/decode.c','sw/ptrocos/media/media_commands.c',
    'sw/ptrocos/media/video_decode.c','sw/ptrocos/media/video_player.c',
    'third_party/fatfs/ff.c','third_party/fatfs/ffunicode.c','sw/tools/fatfs_native.c',
    'sw/tools/storage_commands_native.c','sw/tools/media_commands_native.c','sw/tools/video_player_native.c']
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
    '-DPTROCOS_STORAGE','-DPTROCOS_GRAPHICS','-DPTROCOS_MEDIA','-DPTROCOS_VIDEO','-DVIDEO_NATIVE_STORAGE',
    '-I'+str(ROOT/'sw/tools/storage_native'),'-I'+str(ROOT/'sw/ptrocos'),
    '-I'+str(ROOT/'sw/ptrocos/storage'),'-I'+str(ROOT/'third_party/fatfs'),
    *[str(ROOT/s) for s in sources],'-o',str(OUT/'video_commands.dll'),'-lwinpthread'],check=True)
dll_directory=os.add_dll_directory(str(Path(shutil.which('gcc.exe')).parent))
lib=C.CDLL(str(OUT/'video_commands.dll'))
WRITE=C.CFUNCTYPE(None,C.c_void_p,C.c_void_p);BYTE=C.CFUNCTYPE(None,C.c_void_p,C.c_uint8)
HOOK=C.CFUNCTYPE(None,C.c_uint,C.c_uint,C.c_void_p)
lib.storage_native_setup.argtypes=[C.POINTER(Transport)];lib.storage_native_transfer.argtypes=[TRANSFER]
lib.ptrocos_storage_command.argtypes=[C.c_uint,C.POINTER(C.c_char_p),WRITE,BYTE,C.c_void_p,C.POINTER(C.c_uint32)]
lib.video_native_hook.argtypes=[HOOK];lib.video_native_value.argtypes=[C.c_uint]
lib.video_native_samples.restype=C.POINTER(C.c_uint16)
checks=0

for kind,prefix,version,high in ((12,0,1,False),(16,0,2,True),(32,0,2,True),(16,2048,2,False),(64,0,2,True)):
    fixture=VideoImage(kind,prefix);model=Model(version,high);model.storage=dict(fixture.initial)
    if high:model.sectors=max(32768,((fixture.total+prefix+1023)//1024)*1024)
    lib.storage_native_setup(C.byref(model.bus))
    def command(*args,cancel_event=None,cancel_io=None,remove_event=None):
        global checks
        output=bytearray();cancel=C.c_uint32();errors=[]
        lib.video_native_reset(0)
        @WRITE
        def write(_,ptr):output.extend(C.string_at(ptr))
        @BYTE
        def byte(_,value):output.append(value)
        @HOOK
        def hook(event,index,pointer):
            try:
                if event in [0,1]:
                    picture=fixture.silent_pictures if len(args)>1 and args[1]=='/SILENT.PTV' else fixture.pictures
                    raw=C.string_at(pointer,2400)
                    assert all(bool(raw[(y*160+x)//8]>>(x&7)&1)==bool(picture[index][y][x]) for y in range(120) for x in range(160))
                if event==3: assert C.cast(pointer,C.POINTER(C.c_uint16))[0]==fixture.samples[index-1]
                if event==4: errors.append('audio underrun')
                if cancel_event==(event,index):cancel.value=1
                if remove_event==(event,index):model.attached=False
            except Exception as error:errors.append(repr(error))
        lib.video_native_hook(hook)
        original=model.bus.transfer
        @TRANSFER
        def transfer(ctx,value):
            if cancel_io is not None and model.transfers>=cancel_io:cancel.value=1
            return original(ctx,value)
        lib.storage_native_transfer(transfer)
        argv=(C.c_char_p*len(args))(*(a.encode() for a in args))
        result=lib.ptrocos_storage_command(len(args),argv,write,byte,None,C.byref(cancel))
        lib.storage_native_transfer(original)
        assert result==1 and not errors,(output,errors)
        if model.exception:raise model.exception
        assert all(lib.video_native_value(index)==0 for index in (2,3,7,8))
        checks+=1;return bytes(output),cancel.value
    assert command('umount')[0]==b'FAT unmounted\r\n'
    assert command('play','/CLIP.PTV')[0]==b'mount the SD card first\r\n'
    assert command('mount')[0].startswith(b'FAT mounted')
    assert command('play')[0]==b'usage: play <path>\r\n'
    assert b'FatFs error=4' in command('play','/MISSING')[0]
    assert command('play','/BAD.PTV')[0]==b'unsupported or malformed media file\r\n'
    for path,expected in [('/CLIP.PTV',2133),('/SILENT.PTV',0)]:
        output,_=command('play',path);assert b'PTV played fps=' in output
        assert lib.video_native_value(1)==expected
    for event,index in [(0,0),(0,2),(1,0),(3,32)]:
        _,cancel=command('play','/CLIP.PTV',cancel_event=(event,index));assert cancel
        assert b'PTV played' in command('play','/CLIP.PTV')[0]
    _,cancel=command('play','/CLIP.PTV',cancel_io=model.transfers+200);assert cancel
    assert command('play','/CLIP.PTV')[0]==b'mount the SD card first\r\n'
    assert command('mount')[0].startswith(b'FAT mounted')
    assert b'FatFs error=' in command('play','/CLIP.PTV',remove_event=(0,0))[0]
    model.attached=True
    assert command('play','/CLIP.PTV')[0]==b'mount the SD card first\r\n'
    assert command('mount')[0].startswith(b'FAT mounted')
    model.read_crc_bad=True
    assert b'FatFs error=' in command('play','/CLIP.PTV')[0]
    model.read_crc_bad=False
    assert command('mount')[0].startswith(b'FAT mounted')
    assert b'PTV played' in command('play','/CLIP.PTV')[0]
    assert command('umount')[0]==b'FAT unmounted\r\n'
    print(f'PTV COMMAND FIXTURE PASS {"exFAT" if kind==64 else f"FAT{kind}"} prefix={prefix} fragmented clocked-PCM bitmap cancel removal CRC retry',flush=True)
print(f'PTV COMMANDS NATIVE PASS checks={checks}',flush=True)
