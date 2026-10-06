"""Mount independent FAT fixtures through real FatFs -> diskio -> SD SPI C driver."""
from concurrent.futures import ThreadPoolExecutor
import ctypes as C
import os
from pathlib import Path
import shutil
import struct
import subprocess
from check_sd_card import Model,Transport,ROOT,OUT

sources=['sw/ptrocos/storage/sd_card.c','sw/ptrocos/storage/storage_disk.c',
         'third_party/fatfs/ff.c','third_party/fatfs/ffunicode.c','sw/tools/fatfs_native.c']
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
    '-I'+str(ROOT/'sw/ptrocos/storage'),'-I'+str(ROOT/'third_party/fatfs'),
    *[str(ROOT/name) for name in sources],'-o',str(OUT/'fatfs.dll'),'-lwinpthread'],check=True)
native_dll_directory=os.add_dll_directory(str(Path(shutil.which('gcc.exe')).parent))
lib=C.CDLL(str(OUT/'fatfs.dll'))
lib.ff_native_mount.argtypes=[C.POINTER(Transport)]
lib.ff_native_read.argtypes=[C.c_char_p,C.c_uint64,C.c_void_p,C.c_uint,C.POINTER(C.c_uint)]
lib.ff_native_write.argtypes=[C.c_char_p,C.c_void_p,C.c_uint,C.c_int,C.POINTER(C.c_uint)]
lib.ff_native_list.argtypes=[C.c_char_p,C.c_void_p,C.c_uint]
lib.ff_native_mkdir.argtypes=[C.c_char_p];lib.ff_native_unlink.argtypes=[C.c_char_p]
lib.ff_native_rename.argtypes=[C.c_char_p,C.c_char_p]
lib.ff_native_sizeof.argtypes=[C.c_uint];lib.ff_native_sizeof.restype=C.c_uint

from fatfs_fixture import Image,u32

checks=0
def call(model,name,*args,expected=0):
    global checks
    result=getattr(lib,name)(*args)
    if model.exception: raise model.exception
    assert result==expected,(name,result,expected)
    checks+=1;return result
def read(model,path,expected,offset=0,capacity=None):
    cap=len(expected)+17 if capacity is None else capacity
    buffer=C.create_string_buffer(cap);count=C.c_uint()
    call(model,'ff_native_read',path.encode(),offset,buffer,cap,C.byref(count))
    assert count.value==len(expected) and buffer.raw[:count.value]==expected
def write(model,path,data,append=0):
    count=C.c_uint();call(model,'ff_native_write',path.encode(),data,len(data),append,C.byref(count))
    assert count.value==len(data)
def listing(model,path='0:/'):
    buffer=C.create_string_buffer(8192);call(model,'ff_native_list',path.encode(),buffer,len(buffer))
    return buffer.value.decode('utf-8').splitlines()

for kind,prefix,version,high in ((12,0,1,False),(16,0,2,True),(32,0,2,True),(16,2048,2,False),(64,0,2,True),(64,2048,2,True)):
    fixture=Image(kind,prefix);model=Model(version,high)
    if high: model.sectors=max(32768,((fixture.total+prefix+1023)//1024)*1024)
    model.storage=dict(fixture.initial)
    call(model,'ff_native_mount',C.byref(model.bus))
    assert listing(model)==['HELLO.TXT','SUBDIR']
    read(model,'0:/hello.txt',fixture.payload)
    read(model,'0:/HELLO.TXT',fixture.payload[400:900],400,500)
    read(model,'0:/SUBDIR/NESTED.BIN',fixture.nested)
    read(model,'0:/HELLO.TXT',b'',5000)
    data=bytes((i*53+7)&255 for i in range(4097));name='A unicode 雪 file.bin'
    write(model,'0:/'+name,data);read(model,'0:/'+name,data)
    assert fixture.read_file(model,name)==data
    suffix=b'APPEND\x00\xff';write(model,'0:/'+name,suffix,1)
    assert fixture.read_file(model,name)==data+suffix
    call(model,'ff_native_rename',('0:/'+name).encode(),b'0:/renamed.bin')
    read(model,'0:/renamed.bin',data+suffix)
    longest='L'*251+'.txt';write(model,'0:/'+longest,b'LFN255')
    assert longest in listing(model) and fixture.read_file(model,longest)==b'LFN255'
    read(model,'0:/'+longest,b'LFN255')
    call(model,'ff_native_mkdir',b'0:/new dir')
    for i in range(18): write(model,f'0:/new dir/FILE{i:02}.TXT',bytes([i]))
    assert len(listing(model,'0:/new dir'))==18
    call(model,'ff_native_unlink',b'0:/new dir',expected=7) # Non-empty directory denied.
    with ThreadPoolExecutor(max_workers=4) as pool:
        jobs=[pool.submit(read,model,'0:/HELLO.TXT',fixture.payload[100:1000],100,900) for _ in range(12)]
        for job in jobs: job.result()
    if kind!=64: assert fixture.fatbytes(model,0)==fixture.fatbytes(model,1),'FAT copies diverged'
    call(model,'ff_native_unlink',b'0:/renamed.bin')
    assert not any(n.lower()=='renamed.bin' for n in listing(model))
    for i in range(18): call(model,'ff_native_unlink',f'0:/new dir/FILE{i:02}.TXT'.encode())
    call(model,'ff_native_unlink',b'0:/new dir')
    call(model,'ff_native_unmount');call(model,'ff_native_mount',None)
    read(model,'0:/'+longest,b'LFN255')
    model.attached=False;buffer=C.create_string_buffer(512);count=C.c_uint()
    call(model,'ff_native_read',b'0:/HELLO.TXT',0,buffer,512,C.byref(count),expected=3)
    model.attached=True;call(model,'ff_native_mount',None);read(model,'0:/HELLO.TXT',fixture.payload)
    call(model,'ff_native_unmount')
    print(f'FATFS FIXTURE PASS {"exFAT" if kind==64 else f"FAT{kind}"} prefix={prefix} UTF8 LFN255 write-append directories concurrent-read removal remount',flush=True)

fixture=Image(64,large=True);model=Model();model.sectors=fixture.total;model.storage=dict(fixture.initial)
call(model,'ff_native_mount',C.byref(model.bus))
assert fixture.root_entries(model)['BIG.BIN'][1]==fixture.large_size
read(model,'0:/BIG.BIN',fixture.large_payload,fixture.large_offset,80)
read(model,'0:/BIG.BIN',fixture.large_payload[16:],1<<32,64)
read(model,'0:/BIG.BIN',b'',(1<<64)-1)
call(model,'ff_native_unmount')

fixture=Image(32);model=Model();model.sectors=fixture.total;model.storage=dict(fixture.initial)
broken=bytearray(model.storage[0]);u32(broken,36,0x200000);model.storage[0]=bytes(broken)
call(model,'ff_native_mount',C.byref(model.bus),expected=13)
assert model.transfers<1000,'Malformed BPB caused excessive I/O'
model.storage[0]=fixture.initial[0];call(model,'ff_native_mount',None)
model.read_crc_bad=True;buffer=C.create_string_buffer(512);count=C.c_uint()
call(model,'ff_native_read',b'0:/HELLO.TXT',0,buffer,512,C.byref(count),expected=1)
assert count.value==0
call(model,'ff_native_mount',None);read(model,'0:/HELLO.TXT',fixture.payload)
call(model,'ff_native_unmount')
print(f'FATFS NATIVE PASS checks={checks} sizes_FATFS_FIL_FILINFO_SD={[lib.ff_native_sizeof(i) for i in range(4)]} official-patches FAT12 FAT16 FAT32 exFAT MBR independent-metadata-decode CRC-error BPB-bounds 64-bit-seek')
