"""Literal fragmented PTV fixtures and independent bitmap/PCM references."""
import struct
from fatfs_fixture import Image,entry

def video(frames=4,fps=15,rate=8000):
    data=bytearray(struct.pack('<4sHHHHIIIII',b'PTV1',32,bool(rate),160,120,fps,frames,rate,2400,0))
    pictures=[];samples=[]
    for frame in range(frames):
        levels=[[((x+frame*13)//16+y//12+frame)&1 for x in range(160)] for y in range(120)]
        pictures.append(levels)
        data.extend(bytes(sum(levels[y][x+b]<<b for b in range(8)) for y in range(120) for x in range(0,160,8)))
        pcm=[(n*257)&65535 for n in range(frame*rate//fps,(frame+1)*rate//fps)]
        samples.extend(pcm);data.extend(struct.pack('<'+'H'*len(pcm),*pcm))
    return bytes(data),pictures,samples

class VideoImage(Image):
    def __init__(self,kind=16,prefix=0,frames=4,fps=15):
        super().__init__(kind,prefix)
        sound,self.pictures,self.samples=video(frames,fps)
        silent,self.silent_pictures,_=video(5,30,0)
        self.files={'CLIP.PTV':sound,'SILENT.PTV':silent,'BAD.PTV':sound[:-1]}
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
