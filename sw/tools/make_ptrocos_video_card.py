"""Build a local 32 MiB FAT16 SD image; never writes a physical disk."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile

def make(source,output,force=False):
    source=Path(source).resolve();output=Path(output).resolve()
    if not source.is_file() or source==output:raise ValueError('Require distinct source PTV and output image')
    if output.exists() and not force:raise FileExistsError(output)
    size=source.stat().st_size
    with source.open('rb') as f:
        h=f.read(32)
        if len(h)!=32:raise ValueError('PTV header truncated')
        magic,header,flags,width,height,fps,frames,rate,bytes_per_frame,reserved=struct.unpack('<4sHHHHIIIII',h)
        if magic!=b'PTV1' or header!=32 or flags!=bool(rate) or (width,height)!=(160,120) or not 10<=fps<=30 or not 0<frames<=fps*3600 or (rate and not 8000<=rate<=16000) or bytes_per_frame!=2400 or reserved or size!=32+frames*2400+(frames*rate//fps)*2:raise ValueError('Invalid PTV')
        f.seek(0);source_hash=hashlib.file_digest(f,'sha256').hexdigest()
    sectors=65536;fat_sectors=256;root_sectors=32;data_sector=1+fat_sectors*2+root_sectors
    video_clusters=(size+511)//512
    readme=b'PtrocOS PTV1 SD card\r\nmount\r\nplay /BADAPPLE.PTV\r\nvideo info\r\ngfx off\r\n'
    if video_clusters+1>sectors-data_sector:raise ValueError('Video does not fit 32 MiB image')
    boot=bytearray(512);boot[:11]=b'\xeb\x3c\x90PTROCOS '
    def u16(offset,value):struct.pack_into('<H',boot,offset,value)
    def u32(offset,value):struct.pack_into('<I',boot,offset,value)
    u16(11,512);boot[13]=1;u16(14,1);boot[16]=2;u16(17,512);u16(19,0);boot[21]=0xf8;u16(22,fat_sectors)
    u16(24,63);u16(26,255);u32(28,0);u32(32,sectors);boot[36]=0x80;boot[38]=0x29
    u32(39,int(source_hash[:8],16));boot[43:54]=b'PTROVIDEO  ';boot[54:62]=b'FAT16   ';boot[510:]=b'\x55\xaa'
    fat=bytearray(fat_sectors*512);struct.pack_into('<HH',fat,0,0xfff8,0xffff)
    for cluster in range(2,2+video_clusters):struct.pack_into('<H',fat,cluster*2,cluster+1 if cluster<video_clusters+1 else 0xffff)
    readme_cluster=2+video_clusters;struct.pack_into('<H',fat,readme_cluster*2,0xffff)
    root=bytearray(root_sectors*512)
    def entry(index,name,cluster,length,attr=32):
        offset=index*32;root[offset:offset+11]=name;root[offset+11]=attr
        struct.pack_into('<H',root,offset+26,cluster);struct.pack_into('<I',root,offset+28,length)
    entry(0,b'PTROVIDEO  ',0,0,8);entry(1,b'BADAPPLEPTV',2,size);entry(2,b'README  TXT',readme_cluster,len(readme))
    output.parent.mkdir(parents=True,exist_ok=True)
    handle,path=tempfile.mkstemp(prefix='.ptv-card-',suffix='.img',dir=output.parent)
    temp=Path(path).resolve();temp.relative_to(output.parent)
    try:
        with os.fdopen(handle,'w+b') as f:
            f.truncate(sectors*512);f.seek(0);f.write(boot);f.write(fat);f.write(fat);f.write(root)
            with source.open('rb') as original:
                while block:=original.read(65536):f.write(block)
            f.seek((data_sector+readme_cluster-2)*512);f.write(readme)
            f.flush();f.seek(data_sector*512);checksum=hashlib.sha256();remaining=size
            while remaining:
                block=f.read(min(65536,remaining));checksum.update(block);remaining-=len(block)
            assert checksum.hexdigest()==source_hash
            f.seek(0);image_hash=hashlib.file_digest(f,'sha256').hexdigest()
        if output.exists() and not force:raise FileExistsError(output)
        os.replace(temp,output)
    finally:
        if temp.exists():temp.unlink()
    result={'format':'FAT16 superfloppy','bytes':sectors*512,'sha256':image_hash,'output':str(output),
        'source':str(source),'source_sha256':source_hash,'file':'BADAPPLE.PTV','file_bytes':size,
        'video_first_cluster':2,'video_clusters':video_clusters,'data_start_sector':data_sector,
        'physical_disk_written':False}
    output.with_suffix(output.suffix+'.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('output',type=Path);p.add_argument('--force',action='store_true');a=p.parse_args()
    result=make(a.source,a.output,a.force)
    print(f"PTV CARD IMAGE PASS bytes={result['bytes']} video_clusters={result['video_clusters']} SHA256={result['sha256']}",flush=True)
if __name__=='__main__':main()
