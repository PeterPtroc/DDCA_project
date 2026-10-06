"""Literal media files and independent pixels/samples for native and pin tests."""
import struct
from fatfs_fixture import Image,entry

class MediaImage(Image):
    def __init__(self,kind=16,prefix=0):
        super().__init__(kind,prefix)
        picture,self.pixels=bmp(321,9)
        sound,self.samples=wav(4801,48000)
        short,self.short_samples=wav(537,8000,8,1)
        top,self.top_pixels=bmp(3,5,32,True,108)
        self.files={'IMAGE.BMP':picture,'SOUND.WAV':sound,'SHORT.WAV':short,
                    'TOP.BMP':top,'BAD.BMP':picture[:-1],'BAD.WAV':sound[:-1]}
        root=bytearray(self.initial[self.rootsector]);cluster=100
        for index,(name,data) in enumerate(self.files.items(),2):
            # Fragment every stream; tests must traverse real FAT links.
            count=(len(data)+511)//512;chain=list(range(cluster,cluster+2*count,2));cluster+=2*count
            for a,b in zip(chain,chain[1:]+[self.eof]):self.setfat(a,b)
            base,extension=name.split('.')
            root[index*32:(index+1)*32]=entry(base.encode().ljust(8)+extension.encode().ljust(3),chain[0],len(data))
            for i,c in enumerate(chain):self.initial[self.clustersector(c)]=data[i*512:(i+1)*512].ljust(512,b'\0')
        self.initial[self.rootsector]=bytes(root)
        for copy in range(2):
            for i in range(self.fatsize):self.initial[prefix+self.reserved+copy*self.fatsize+i]=bytes(self.fat[i*512:(i+1)*512])

def bmp(width,height,bits=24,top=False,dib=40):
    # Distinct channels and row orientation expose RGB/BGR, padding and reversal.
    rows=[];expected=[]
    for y in range(height):
        row=bytearray();colors=[]
        for x in range(width):
            red,green,blue=(x*31+y*11)&255,(x*7+y*29)&255,(x*13+y*3)&255
            row.extend((blue,green,red))
            if bits==32: row.append((x+y)&255)
            colors.append((red//8)*2048+(green//4)*32+blue//8)
        row.extend(bytes((-len(row))%4));rows.append(bytes(row));expected.append(colors+[0]*(640-width))
    expected.extend([[0]*640 for _ in range(480-height)])
    data=b''.join(rows if top else reversed(rows));offset=14+dib
    head=struct.pack('<2sIHHI',b'BM',offset+len(data),0,0,offset)
    head+=struct.pack('<IiiHHIIiiII',dib,width,-height if top else height,1,bits,0,len(data),0,0,0,0)
    return head+bytes(dib-40)+data,expected

def chunk(name,data):return name+struct.pack('<I',len(data))+data+bytes(len(data)&1)
def wav(frames=537,rate=44100,bits=16,channels=2,data_first=False):
    raw=bytearray();expected=[]
    for i in range(frames):
        signed=[]
        for channel in range(channels):
            if bits==8:
                value=(i*37+channel*11)&255;raw.append(value);signed.append((value-128)*256)
            else:
                value=(i*12345+channel*49153)&65535;raw.extend(struct.pack('<H',value))
                signed.append(value if value<32768 else value-65536)
        total=sum(signed);mean=(abs(total)//channels)*(1 if total>=0 else -1)
        expected.append(mean+32768)
    fmt=struct.pack('<HHIIHH',1,channels,rate,rate*channels*(bits//8),channels*(bits//8),bits)
    chunks=[chunk(b'fmt ',fmt),chunk(b'data',raw)]
    if data_first:chunks.reverse()
    body=b'WAVE'+chunk(b'JUNK',b'abc')+b''.join(chunks)+chunk(b'LIST',b'after data')
    return b'RIFF'+struct.pack('<I',len(body))+body,expected
