"""ELF loader through actual FatFs, diskio and SD driver; independent memory."""
import ctypes as C
import os
from pathlib import Path
import shutil
import struct
import subprocess
from check_sd_card import Model,Transport,TRANSFER,ROOT
from check_elf_decode import Image,expected_memory,CODE,DATA,CODE_END,DATA_END
from elf_fixture import ElfImage
OUT=ROOT/'build/ptrocos_elf';OUT.mkdir(parents=True,exist_ok=True)
sources=['sw/ptrocos/storage/sd_card.c','sw/ptrocos/storage/storage_disk.c',
    'sw/ptrocos/storage/storage_commands.c','sw/ptrocos/shell.c','sw/ptrocos/elf/elf_decode.c',
    'third_party/fatfs/ff.c','third_party/fatfs/ffunicode.c','sw/tools/fatfs_native.c',
    'sw/tools/storage_commands_native.c','sw/tools/elf_storage_native.c']
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
    '-DPTROCOS_STORAGE','-DPTROCOS_ELF','-I'+str(ROOT/'sw/tools/storage_native'),
    '-I'+str(ROOT/'sw/ptrocos'),'-I'+str(ROOT/'sw/ptrocos/storage'),'-I'+str(ROOT/'third_party/fatfs'),
    *[str(ROOT/s) for s in sources],'-o',str(OUT/'elf_storage.dll'),'-lwinpthread'],check=True)
dll_directory=os.add_dll_directory(str(Path(shutil.which('gcc.exe')).parent))
lib=C.CDLL(str(OUT/'elf_storage.dll'))
WRITE=C.CFUNCTYPE(None,C.c_void_p,C.c_void_p);BYTE=C.CFUNCTYPE(None,C.c_void_p,C.c_uint8)
SINK=C.CFUNCTYPE(C.c_int,C.c_uint32,C.c_void_p,C.c_uint)
lib.storage_native_setup.argtypes=[C.POINTER(Transport)];lib.storage_native_transfer.argtypes=[TRANSFER]
lib.ptrocos_storage_command.argtypes=[C.c_uint,C.POINTER(C.c_char_p),WRITE,BYTE,C.c_void_p,C.POINTER(C.c_uint32)]
lib.ptrocos_storage_elf.argtypes=[C.c_char_p,C.POINTER(Image),WRITE,C.c_void_p,C.POINTER(C.c_uint32)]
lib.elf_native_sink.argtypes=[SINK]
checks=0
for kind,prefix,version,high in ((12,0,1,False),(16,0,2,True),(32,0,2,True),(16,2048,2,False)):
    fixture=ElfImage(kind,prefix);model=Model(version,high);model.storage=dict(fixture.initial)
    if high:model.sectors=max(32768,((fixture.total+prefix+1023)//1024)*1024)
    lib.storage_native_setup(C.byref(model.bus))
    def command(name):
        global checks
        output=bytearray();cancel=C.c_uint32()
        @WRITE
        def write(_,ptr):output.extend(C.string_at(ptr))
        @BYTE
        def byte(_,value):output.append(value)
        args=(C.c_char_p*1)(name.encode())
        assert lib.ptrocos_storage_command(1,args,write,byte,None,C.byref(cancel))==1
        checks+=1;return bytes(output)
    def load(path,expected=0,cancel_write=None,cancel_io=None,remove_write=None):
        global checks
        output=bytearray();cancel=C.c_uint32();image=Image()
        code=bytearray(b'\xcc'*(CODE_END-CODE));data=bytearray(b'\xcc'*(DATA_END-DATA));writes=[];errors=[]
        @WRITE
        def write(_,ptr):output.extend(C.string_at(ptr))
        @SINK
        def sink(address,ptr,count):
            try:
                if CODE<=address and address+count<=CODE_END:target,base=code,CODE
                elif DATA<=address and address+count<=DATA_END:target,base=data,DATA
                else:raise AssertionError('destination bounds')
                target[address-base:address-base+count]=C.string_at(ptr,count);writes.append((address,count))
                if cancel_write==len(writes):cancel.value=1
                if remove_write==len(writes):model.attached=False
                return 0
            except Exception as error:errors.append(repr(error));return 6
        lib.elf_native_sink(sink)
        original=model.bus.transfer
        @TRANSFER
        def transfer(ctx,value):
            if cancel_io is not None and model.transfers>=cancel_io:cancel.value=1
            return original(ctx,value)
        lib.storage_native_transfer(transfer)
        result=lib.ptrocos_storage_elf(path.encode(),C.byref(image),write,None,C.byref(cancel))
        lib.storage_native_transfer(original)
        assert result==expected,(path,result,output)
        assert image.loaded==(result==0) and not errors
        if model.exception:raise model.exception
        if not result:
            assert (code,data)==expected_memory(fixture.files[path[1:]])
            assert image.abi_version==1 and image.entry==CODE
        if result in (1,2,3):assert not writes,'invalid ELF wrote memory'
        checks+=1;return bytes(output),writes
    assert command('umount')==b'FAT unmounted\r\n'
    assert load('/HELLO.ELF',4)[0]==b'mount the SD card first\r\n'
    assert command('mount').startswith(b'FAT mounted')
    load('/BAD.ELF',3)
    for path in ('/HELLO.ELF','/FAULT.ELF','/LOOP.ELF'):load(path)
    load('/MISSING.ELF',4)
    for n in (1,2,3):
        load('/HELLO.ELF',5,cancel_write=n);load('/HELLO.ELF')
    load('/HELLO.ELF',5,cancel_io=model.transfers+50)
    load('/HELLO.ELF',4)
    assert command('mount').startswith(b'FAT mounted')
    load('/HELLO.ELF',4,remove_write=1);model.attached=True
    load('/HELLO.ELF',4)
    assert command('mount').startswith(b'FAT mounted')
    model.read_crc_bad=True;load('/HELLO.ELF',4);model.read_crc_bad=False
    assert command('mount').startswith(b'FAT mounted')
    load('/HELLO.ELF');assert command('umount')==b'FAT unmounted\r\n'
    print(f'ELF STORAGE FIXTURE PASS FAT{kind} prefix={prefix} fragmented exact-copy BSS cancel removal CRC retry',flush=True)
print(f'ELF STORAGE NATIVE PASS checks={checks}',flush=True)
