"""Mount generated FAT16 image with real FatFs/SD and hash the complete PTV."""
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
from check_sd_card import Model,Transport,ROOT

def main():
    p=argparse.ArgumentParser();p.add_argument('image',type=Path);a=p.parse_args()
    out=ROOT/'build/ptrocos_video';meta=json.loads(a.image.with_suffix(a.image.suffix+'.json').read_text(encoding='utf-8'))
    sources=['sw/ptrocos/storage/sd_card.c','sw/ptrocos/storage/storage_disk.c','third_party/fatfs/ff.c','third_party/fatfs/ffunicode.c','sw/tools/fatfs_native.c']
    subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
        '-I'+str(ROOT/'sw/ptrocos/storage'),'-I'+str(ROOT/'third_party/fatfs'),
        *[str(ROOT/s) for s in sources],'-o',str(out/'video_card.dll'),'-lwinpthread'],check=True)
    dll_directory=os.add_dll_directory(str(Path(shutil.which('gcc.exe')).parent));lib=C.CDLL(str(out/'video_card.dll'))
    lib.ff_native_mount.argtypes=[C.POINTER(Transport)]
    lib.ff_native_read.argtypes=[C.c_char_p,C.c_uint64,C.c_void_p,C.c_uint,C.POINTER(C.c_uint)]
    lib.ff_native_list.argtypes=[C.c_char_p,C.c_void_p,C.c_uint]
    raw=a.image.read_bytes();assert hashlib.sha256(raw).hexdigest()==meta['sha256'] and len(raw)==33554432
    model=Model(2,True);model.sectors=len(raw)//512
    model.storage={sector:raw[sector*512:(sector+1)*512] for sector in range(model.sectors) if any(raw[sector*512:(sector+1)*512])}
    assert lib.ff_native_mount(C.byref(model.bus))==0
    listing=C.create_string_buffer(1024);assert lib.ff_native_list(b'0:/',listing,1024)==0
    assert listing.value==b'BADAPPLE.PTV\nREADME.TXT\n',listing.value
    buffer=C.create_string_buffer(meta['file_bytes']+1);got=C.c_uint()
    assert lib.ff_native_read(b'0:/BADAPPLE.PTV',0,buffer,len(buffer),C.byref(got))==0
    assert got.value==meta['file_bytes']
    actual=hashlib.sha256(buffer.raw[:got.value]).hexdigest();assert actual==meta['source_sha256']
    assert lib.ff_native_unmount()==0
    if model.exception:raise model.exception
    result={'filesystem':'FAT16','whole_file_read_bytes':got.value,'file_sha256':actual,
        'image_sha256':meta['sha256'],'sector_reads':sum(cmd==17 for cmd,argument in model.commands),
        'physical_card_verified':False}
    a.image.with_suffix(a.image.suffix+'.verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(f'PTV CARD FATFS VERIFY PASS bytes={got.value} SHA256={actual}',flush=True)
if __name__=='__main__':main()
