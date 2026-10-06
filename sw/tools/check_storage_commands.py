"""Exercise actual shell storage commands through FatFs, diskio and SD SPI.

Expected file bytes and rows come from independent literal FAT fixtures.
Only the FreeRTOS scheduler and board transport are native adapters.
"""
from concurrent.futures import ThreadPoolExecutor
from threading import Event
import ctypes as C
import os
from pathlib import Path
import random
import shutil
import subprocess
from check_sd_card import Model, Transport, TRANSFER, ROOT
from fatfs_fixture import Image

OUT=ROOT/'build/ptrocos_files';OUT.mkdir(parents=True,exist_ok=True)
sources=['sw/ptrocos/storage/sd_card.c','sw/ptrocos/storage/storage_disk.c',
         'sw/ptrocos/storage/storage_commands.c','sw/ptrocos/shell.c',
         'third_party/fatfs/ff.c','third_party/fatfs/ffunicode.c',
         'sw/tools/fatfs_native.c','sw/tools/storage_commands_native.c']
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
    '-DPTROCOS_STORAGE','-I'+str(ROOT/'sw/tools/storage_native'),
    '-I'+str(ROOT/'sw/ptrocos'),'-I'+str(ROOT/'sw/ptrocos/storage'),
    '-I'+str(ROOT/'third_party/fatfs'),*[str(ROOT/name) for name in sources],
    '-o',str(OUT/'storage_commands.dll'),'-lwinpthread'],check=True)
dll_directory=os.add_dll_directory(str(Path(shutil.which('gcc.exe')).parent))
lib=C.CDLL(str(OUT/'storage_commands.dll'))
WRITE=C.CFUNCTYPE(None,C.c_void_p,C.c_void_p)
BYTE=C.CFUNCTYPE(None,C.c_void_p,C.c_uint8)
lib.storage_native_setup.argtypes=[C.POINTER(Transport)]
lib.storage_native_transfer.argtypes=[TRANSFER]
lib.ptrocos_storage_command.argtypes=[C.c_uint,C.POINTER(C.c_char_p),WRITE,BYTE,C.c_void_p,C.POINTER(C.c_uint32)]
lib.ff_native_write.argtypes=[C.c_char_p,C.c_void_p,C.c_uint,C.c_int,C.POINTER(C.c_uint)]
lib.shell_complete.argtypes=[C.c_char_p];lib.shell_complete.restype=C.c_char_p
checks=0

def command(model,*args,cancel_after=None,cancel_io=None,pre_cancel=False,hold_output=None):
    global checks
    captured=bytearray();cancel=C.c_uint32(int(pre_cancel));exceptions=[]
    def collect(data):
        if cancel.value: return
        captured.extend(data)
        if hold_output is not None and not hold_output[0].is_set():
            hold_output[0].set();assert hold_output[1].wait(5),'Timed out releasing output owner'
        if cancel_after is not None and len(captured)>=cancel_after: cancel.value=1
    def text(ctx,ptr):
        try: collect(C.string_at(ptr))
        except Exception as e: exceptions.append(e)
    def byte(ctx,value):
        try: collect(bytes([value]))
        except Exception as e: exceptions.append(e)
    write=WRITE(text);write_byte=BYTE(byte)
    callback=None
    if cancel_io is not None:
        # The production command's cancel pointer changes during real driver I/O.
        original= model.bus.transfer
        target=model.transfers+cancel_io
        def transfer(ctx,value):
            if model.transfers>=target: cancel.value=1
            return original(ctx,value)
        callback=TRANSFER(transfer);lib.storage_native_transfer(callback)
    argv=(C.c_char_p*len(args))(*(a.encode('utf-8') for a in args))
    handled=lib.ptrocos_storage_command(len(args),argv,write,write_byte,None,C.byref(cancel))
    if model.exception: raise model.exception
    if exceptions: raise exceptions[0]
    assert handled==(bool(args) and args[0] in ('mount','umount','sdinfo','fscheck','ls','cat','hexdump'))
    checks+=1
    if callback is not None: lib.storage_native_transfer(original)
    return bytes(captured),cancel.value

def expect(model,args,expected,**options):
    actual,cancel=command(model,*args,**options)
    assert actual==expected,(args,actual[:200],expected[:200],len(actual),len(expected))
    return cancel

def dump(data,offset=0,count=256,base=0):
    result=[]
    for pos in range(offset,min(len(data),offset+count),16):
        row=data[pos:min(pos+16,offset+count)]
        left=' '.join(f'{b:02x}' for b in row[:8]).ljust(23)
        right=' '.join(f'{b:02x}' for b in row[8:]).ljust(23)
        ascii_text=''.join(chr(b) if 32<=b<127 else '.' for b in row).ljust(16)
        address=pos+base;width=16 if address>0xffffffff else 8
        result.append(f'{address:0{width}x}  {left}  {right}  |{ascii_text}|\r\n')
    return ''.join(result).encode()

rng=random.Random(0x707)
for kind,prefix,version,high in ((12,0,1,False),(16,0,2,True),(32,0,2,True),(16,2048,2,False),(64,0,2,True),(64,2048,2,True)):
    fixture=Image(kind,prefix);model=Model(version,high)
    if high: model.sectors=max(32768,((fixture.total+prefix+1023)//1024)*1024)
    model.storage=dict(fixture.initial);lib.storage_native_setup(C.byref(model.bus))
    expect(model,('umount',),b'FAT unmounted\r\n')
    for args in (('ls',),('cat','/HELLO.TXT'),('hexdump','/HELLO.TXT')):
        expect(model,args,b'mount the SD card first\r\n')
    # FatFs FS_FAT12/16/32/EXFAT are 1/2/3/4.
    mounted=f'FAT mounted type={ {12:1,16:2,32:3,64:4}[kind]} sectors={model.sectors}\r\n'.encode()
    expect(model,('mount',),mounted)
    root=b'f 1100 HELLO.TXT\r\nd 0 SUBDIR\r\n'
    for path in (None,'/','0:/'):
        expect(model,('ls',) if path is None else ('ls',path),root)
    expect(model,('ls','/SUBDIR'),b'f 256 NESTED.BIN\r\n')
    expect(model,('ls','/hello.txt'),b'f 1100 HELLO.TXT\r\n')
    expect(model,('cat','/HELLO.TXT'),fixture.payload)
    expect(model,('cat','/SUBDIR/NESTED.BIN'),fixture.nested)
    expect(model,('hexdump','/HELLO.TXT'),dump(fixture.payload))
    expect(model,('hexdump','/HELLO.TXT','500'),dump(fixture.payload,500))
    for offset,count in ((0,0),(0,1),(1,16),(15,17),(500,40),(1023,78),(1099,100),(1100,256),
                         (5000,256),(4294967295,4096),(0,4096),*((rng.randrange(1200),rng.randrange(4100)) for _ in range(35))):
        if count>4096: continue
        expect(model,('hexdump','/HELLO.TXT',str(offset),str(count)),dump(fixture.payload,offset,count))
    for args in (('ls','/','extra'),('cat',),('cat','/HELLO.TXT','extra'),('hexdump',),
                 ('hexdump','/HELLO.TXT','-1'),('hexdump','/HELLO.TXT','0x10'),
                 ('hexdump','/HELLO.TXT','18446744073709551616'),('hexdump','/HELLO.TXT','0','4097'),
                 ('hexdump','/HELLO.TXT','0','x'),('hexdump','/HELLO.TXT','0','1','extra')):
        before=model.transfers;result,_=command(model,*args)
        assert result.startswith(b'usage:') and model.transfers==before
    for name in ('ls','cat','hexdump'):
        result,_=command(model,name,'/missing');assert result.startswith(b'FatFs error=')
    # Create UTF-8/LFN and empty fixtures through the independently verified FatFs API.
    unicode_name='A unicode 雪 file.bin';data=b'line one\r\nline two\n\x00\xff\x1b'+bytes(range(256))*18
    for name,value in ((unicode_name,data),('EMPTY.TXT',b'')):
        count=C.c_uint();assert lib.ff_native_write(('/'+name).encode(),value,len(value),0,C.byref(count))==0
        assert count.value==len(value)
        assert fixture.read_file(model,name)==value if value else fixture.root_entries(model)[name][:2]==(0,0)
    expect(model,('cat','/'+unicode_name),data)
    expect(model,('hexdump','/'+unicode_name,'0','4096'),dump(data,0,4096))
    expect(model,('cat','/EMPTY.TXT'),b'')
    expect(model,('hexdump','/EMPTY.TXT'),b'')
    expect(model,('ls','/EMPTY.TXT'),b'f 0 EMPTY.TXT\r\n')
    longest='L'*251+'.txt';value=b'LFN'
    count=C.c_uint();assert lib.ff_native_write(('/'+longest).encode(),value,len(value),0,C.byref(count))==0
    assert fixture.read_file(model,longest)==value
    expect(model,('ls','/'+longest),('f 3 '+longest+'\r\n').encode())
    expect(model,('cat','/'+longest),value)
    result,_=command(model,'ls');assert (f'f {len(data)} {unicode_name}\r\n').encode() in result
    assert expect(model,('cat','/'+unicode_name),data[:513],cancel_after=513)
    expect(model,('cat','/HELLO.TXT'),fixture.payload) # Output cancellation preserves the mount.
    actual,cancel=command(model,'hexdump','/'+unicode_name,'0','4096',cancel_after=80)
    assert cancel and actual==dump(data,0,16)
    expect(model,('ls',),b'',pre_cancel=True)
    actual,cancel=command(model,'ls',cancel_after=1);assert cancel and actual==b'f '
    expect(model,('cat','/HELLO.TXT'),fixture.payload)
    before_writes=sum(cmd==24 for cmd,arg in model.commands)
    with ThreadPoolExecutor(max_workers=4) as pool:
        jobs=[pool.submit(expect,model,('cat','/HELLO.TXT'),fixture.payload) for _ in range(12)]
        for job in jobs: job.result()
    assert sum(cmd==24 for cmd,arg in model.commands)==before_writes,'File commands wrote to the card'
    entered,release=Event(),Event()
    with ThreadPoolExecutor(max_workers=2) as pool:
        owner=pool.submit(command,model,'cat','/HELLO.TXT',hold_output=(entered,release))
        assert entered.wait(5)
        before=model.transfers
        expect(model,('ls',),b'',pre_cancel=True) # Cancel while the other TTY owns FatFs.
        assert model.transfers==before
        release.set();assert owner.result()[0]==fixture.payload
    assert lib.storage_native_yields()>20
    # Cancellation in a sector transaction invalidates the card and mount; remount recovers.
    actual,cancel=command(model,'cat','/HELLO.TXT',cancel_io=30)
    assert cancel and actual==b'' and not model.selected
    expect(model,('ls',),b'mount the SD card first\r\n')
    lib.storage_native_setup(C.byref(model.bus))
    expect(model,('mount',),mounted);expect(model,('cat','/HELLO.TXT'),fixture.payload)
    model.read_crc_bad=True
    actual,_=command(model,'cat','/HELLO.TXT');assert actual==b'FatFs error=1 SD=crc\r\n'
    expect(model,('ls',),b'mount the SD card first\r\n')
    expect(model,('mount',),mounted)
    model.attached=False
    actual,_=command(model,'hexdump','/HELLO.TXT');assert actual.startswith(b'FatFs error=3 SD=no-card')
    model.attached=True;expect(model,('mount',),mounted)
    expect(model,('ls','/SUBDIR'),b'f 256 NESTED.BIN\r\n')
    expect(model,('umount',),b'FAT unmounted\r\n')
    print(f'STORAGE COMMAND FIXTURE PASS {"exFAT" if kind==64 else f"FAT{kind}"} prefix={prefix} raw-bytes Unicode offsets cancel CRC removal remount mutex',flush=True)
fixture=Image(64,large=True);model=Model();model.sectors=fixture.total;model.storage=dict(fixture.initial)
lib.storage_native_setup(C.byref(model.bus))
expect(model,('mount',),f'FAT mounted type=4 sectors={model.sectors}\r\n'.encode())
expect(model,('ls','/BIG.BIN'),f'f {fixture.large_size} BIG.BIN\r\n'.encode())
expect(model,('hexdump','/BIG.BIN',str(fixture.large_offset),'80'),dump(fixture.large_payload,count=80,base=fixture.large_offset))
expect(model,('hexdump','/BIG.BIN','18446744073709551615'),b'')
expect(model,('umount',),b'FAT unmounted\r\n')
for prefix,name in ((b'ls',b'ls'),(b'ca',b'cat'),(b'hex',b'hexdump')): assert lib.shell_complete(prefix)==name
assert lib.shell_complete(b'c') is None
command(model);command(model,'other')
print(f'PTROCOS FILE COMMANDS NATIVE PASS checks={checks} FAT12 FAT16 FAT32 exFAT MBR binary-cat independent-hexdump concurrent-read cleanup 64-bit-size-offset')
