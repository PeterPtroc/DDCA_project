"""Actual compiled application files in independent fragmented FAT chains."""
from pathlib import Path
import hashlib
import json
from fatfs_fixture import Image,entry

class ElfImage(Image):
    def __init__(self,kind=16,prefix=0):
        super().__init__(kind,prefix)
        folder=Path(__file__).resolve().parents[2]/'build/ptrocos_elf/apps'
        self.files={name.upper()+'.ELF':(folder/(name+'.elf')).read_bytes() for name in ('hello','fault','loop')}
        bad=bytearray(self.files['HELLO.ELF']);bad[36]=1
        self.files['BAD.ELF']=bytes(bad)
        if kind==64:
            for name,data in self.files.items():self.add_exfat_file(name,data)
            return
        root=bytearray(self.initial[self.rootsector]);cluster=100
        for index,(name,data) in enumerate(self.files.items(),2):
            count=(len(data)+511)//512;chain=list(range(cluster,cluster+2*count,2));cluster+=2*count
            for a,b in zip(chain,chain[1:]+[self.eof]):self.setfat(a,b)
            base,extension=name.split('.')
            root[index*32:(index+1)*32]=entry(base.encode().ljust(8)+extension.encode().ljust(3),chain[0],len(data))
            for i,c in enumerate(chain):self.initial[self.clustersector(c)]=data[i*512:(i+1)*512].ljust(512,b'\0')
        self.initial[self.rootsector]=bytes(root)
        for copy in range(2):
            for i in range(self.fatsize):self.initial[prefix+self.reserved+copy*self.fatsize+i]=bytes(self.fat[i*512:(i+1)*512])

if __name__=='__main__':
    out=Path('build/ptrocos_elf/elf-fat16.hex');fixture=ElfImage()
    with out.open('w',encoding='ascii') as f:
        for sector,data in sorted(fixture.initial.items()):
            f.write(f'@{sector*512:x}\n')
            for i in range(0,512,32):f.write(' '.join(f'{x:02x}' for x in data[i:i+32])+'\n')
    image=out.with_name('ELF-SD.img')
    with image.open('w+b') as f:
        f.truncate(fixture.total*512)
        for sector,data in fixture.initial.items():
            assert len(data)==512 and sector<fixture.total
            f.seek(sector*512);f.write(data)
        f.flush();f.seek(0);checksum=hashlib.file_digest(f,'sha256').hexdigest()
    manifest={'format':'FAT16 superfloppy','bytes':fixture.total*512,'sha256':checksum,
              'files':{name:{'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,data in fixture.files.items()},
              'fragmented':True,'physical_disk_written':False}
    image.with_suffix('.img.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print(f'ELF FAT16 FIXTURE PASS files={len(fixture.files)} sectors={len(fixture.initial)} fragmented')
