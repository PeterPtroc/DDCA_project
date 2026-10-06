"""Independent literal FAT/exFAT fixtures shared by native and pin-level tests."""
import struct

def u16(data,offset,value): struct.pack_into('<H',data,offset,value)
def u32(data,offset,value): struct.pack_into('<I',data,offset,value)
def u64(data,offset,value): struct.pack_into('<Q',data,offset,value)
def checksum(data,bits=16,skip=()):
    value=0;mask=(1<<bits)-1
    for i,byte in enumerate(data):
        if i not in skip: value=(((value>>1)|((value&1)<<(bits-1)))+byte)&mask
    return value
def upper_unit(unit):
    upper=chr(unit).upper()
    return ord(upper) if len(upper)==1 and ord(upper)<=65535 else unit
def exfat_entry(name,cluster,size,attribute=32,contiguous=False):
    encoded=name.encode('utf-16-le');units=len(encoded)//2
    data=bytearray((2+(units+14)//15)*32);data[0]=0x85;data[1]=len(data)//32-1
    u16(data,4,attribute);data[32]=0xc0;data[33]=3 if contiguous else 1;data[35]=units
    uppercase=b''.join(struct.pack('<H',upper_unit(unit)) for (unit,) in struct.iter_unpack('<H',encoded))
    u16(data,36,checksum(uppercase));u64(data,40,size);u32(data,52,cluster);u64(data,56,size)
    for i in range((units+14)//15):
        pos=(i+2)*32;data[pos]=0xc1;part=encoded[i*30:(i+1)*30];data[pos+2:pos+2+len(part)]=part
    u16(data,2,checksum(data,skip=(2,3)))
    return data
def entry(name,cluster,size,attribute=32):
    data=bytearray(32);data[:11]=name;data[11]=attribute
    u16(data,20,cluster>>16);u16(data,26,cluster&65535);u32(data,28,size)
    return data

class Image:
    def __init__(self,kind,prefix=0,large=False):
        self.kind,self.prefix=kind,prefix
        if kind==64:
            self._init_exfat(large);return
        self.total={12:2048,16:16384,32:131072}[kind]
        self.reserved=32 if kind==32 else 1
        self.fatsize={12:6,16:64,32:1024}[kind]
        self.rootcount=0 if kind==32 else 64
        self.data=self.reserved+2*self.fatsize+self.rootcount//16
        self.initial={};self.payload=bytes((i*37+11)&255 for i in range(1100))
        self.nested=bytes(range(256));boot=bytearray(512)
        boot[:11]=b'\xeb\x58\x90PTROCOS '
        u16(boot,11,512);boot[13]=1;u16(boot,14,self.reserved);boot[16]=2
        u16(boot,17,self.rootcount);u16(boot,19,self.total if self.total<65536 else 0)
        boot[21]=0xf8;u16(boot,22,0 if kind==32 else self.fatsize)
        u16(boot,24,63);u16(boot,26,255);u32(boot,28,prefix)
        u32(boot,32,self.total if self.total>=65536 else 0)
        boot[510:]=b'\x55\xaa'
        self.fat=bytearray(self.fatsize*512)
        if kind==32:
            u32(boot,36,self.fatsize);u32(boot,44,2);u16(boot,48,1);u16(boot,50,6)
            boot[64]=0x80;boot[66]=0x29;boot[71:82]=b'PTROCOS    ';boot[82:90]=b'FAT32   '
            fsinfo=bytearray(512);u32(fsinfo,0,0x41615252);u32(fsinfo,484,0x61417272)
            u32(fsinfo,488,self.total-self.data-6);u32(fsinfo,492,9);u32(fsinfo,508,0xaa550000)
            self.initial[prefix+1]=bytes(fsinfo);self.initial[prefix+7]=bytes(fsinfo)
            self.file_chain=[3,7,4];self.subcluster=5;self.nestcluster=8
            self.setfat(0,0x0ffffff8);self.setfat(1,0x0fffffff);self.setfat(2,0x0fffffff)
        else:
            boot[36]=0x80;boot[38]=0x29;boot[43:54]=b'PTROCOS    '
            boot[54:62]=b'FAT12   ' if kind==12 else b'FAT16   '
            self.file_chain=[2,5,3];self.subcluster=4;self.nestcluster=6
            self.setfat(0,0xff8 if kind==12 else 0xfff8);self.setfat(1,self.eof)
        self.initial[prefix]=bytes(boot)
        if kind==32: self.initial[prefix+6]=bytes(boot)
        for a,b in zip(self.file_chain,self.file_chain[1:]+[self.eof]): self.setfat(a,b)
        self.setfat(self.subcluster,self.eof);self.setfat(self.nestcluster,self.eof)
        for copy in range(2):
            for i in range(self.fatsize): self.initial[prefix+self.reserved+copy*self.fatsize+i]=bytes(self.fat[i*512:(i+1)*512])
        root=bytearray(512)
        root[:32]=entry(b'HELLO   TXT',self.file_chain[0],len(self.payload))
        root[32:64]=entry(b'SUBDIR     ',self.subcluster,0,16)
        self.initial[self.rootsector]=bytes(root)
        subdir=bytearray(512)
        subdir[:32]=entry(b'.          ',self.subcluster,0,16)
        subdir[32:64]=entry(b'..         ',2 if kind==32 else 0,0,16)
        subdir[64:96]=entry(b'NESTED  BIN',self.nestcluster,len(self.nested))
        self.initial[self.clustersector(self.subcluster)]=bytes(subdir)
        self.initial[self.clustersector(self.nestcluster)]=self.nested+bytes(256)
        for i,cluster in enumerate(self.file_chain):
            self.initial[self.clustersector(cluster)]=self.payload[i*512:(i+1)*512].ljust(512,b'\0')
        if prefix:
            mbr=bytearray(512);mbr[446]=0x80;mbr[450]=6
            u32(mbr,454,prefix);u32(mbr,458,self.total);mbr[510:]=b'\x55\xaa';self.initial[0]=bytes(mbr)
    @property
    def eof(self): return {12:0xfff,16:0xffff,32:0x0fffffff,64:0xffffffff}[self.kind]
    @property
    def rootsector(self):
        return self.clustersector(2) if self.kind in (32,64) else self.prefix+self.reserved+2*self.fatsize
    def clustersector(self,cluster): return self.prefix+self.data+(cluster-2)*getattr(self,'csize',1)
    def setfat(self,cluster,value):
        if self.kind==12:
            offset=cluster*3//2;old=int.from_bytes(self.fat[offset:offset+2],'little')
            new=(old&0xf)|(value<<4) if cluster&1 else (old&0xf000)|value
            self.fat[offset:offset+2]=new.to_bytes(2,'little')
        elif self.kind==16: u16(self.fat,cluster*2,value)
        else: u32(self.fat,cluster*4,value)
    def fatbytes(self,model,copy=0):
        if self.kind==64: assert copy==0
        return b''.join(model.storage.get(self.prefix+self.reserved+copy*self.fatsize+i,bytes(512)) for i in range(self.fatsize))
    def chain(self,model,first):
        table=self.fatbytes(model);result=[];cluster=first
        while cluster<self.eof-7:
            assert cluster>=2 and cluster not in result,'Cyclic or invalid FAT chain'
            result.append(cluster)
            if self.kind==12:
                value=int.from_bytes(table[cluster*3//2:cluster*3//2+2],'little')
                cluster=(value>>4 if cluster&1 else value)&0xfff
            elif self.kind==16: cluster=struct.unpack_from('<H',table,cluster*2)[0]
            else:
                cluster=struct.unpack_from('<I',table,cluster*4)[0]
                if self.kind==32: cluster&=0x0fffffff
        return result
    def root_entries(self,model):
        if self.kind==64: return self._exfat_entries(model)
        sectors=[self.clustersector(c) for c in self.chain(model,2)] if self.kind==32 else list(range(self.rootsector,self.rootsector+self.rootcount//16))
        data=b''.join(model.storage.get(s,bytes(512)) for s in sectors);names={};lfn={};checksum=None
        for pos in range(0,len(data),32):
            row=data[pos:pos+32]
            if row[0]==0: break
            if row[0]==0xe5: lfn={};continue
            if row[11]==15:
                if row[0]&64: lfn={};checksum=row[13]
                assert (row[0]&31)>0 and row[13]==checksum
                lfn[row[0]&31]=row[1:11]+row[14:26]+row[28:32];continue
            short=row[:11];actual_checksum=0
            for byte in short: actual_checksum=((actual_checksum>>1)+((actual_checksum&1)<<7)+byte)&255
            if lfn:
                assert checksum==actual_checksum and set(lfn)==set(range(1,len(lfn)+1))
                units=b''.join(lfn[i] for i in range(1,len(lfn)+1))
                name=units.decode('utf-16-le').split('\0')[0].rstrip('\uffff')
            else: name=short[:8].decode().rstrip()+('.'+short[8:].decode().rstrip() if short[8:].strip() else '')
            cluster=struct.unpack_from('<H',row,26)[0]|(struct.unpack_from('<H',row,20)[0]<<16)
            names[name]=(cluster,struct.unpack_from('<I',row,28)[0],row[11]);lfn={}
        return names
    def read_file(self,model,name):
        first,length,attr=self.root_entries(model)[name]
        assert not attr&16
        if self.kind==64:
            chain=self._exfat_chains[name]
            bitmap=b''.join(model.storage.get(self.clustersector(3)+i,bytes(512)) for i in range((self.ncl+4095)//4096))
            assert all(bitmap[(c-2)//8]&(1<<((c-2)%8)) for c in chain),'Unallocated exFAT file cluster'
            return b''.join(model.storage.get(self.clustersector(c)+i,bytes(512)) for c in chain for i in range(self.csize))[:length]
        return b''.join(model.storage.get(self.clustersector(c),bytes(512)) for c in self.chain(model,first))[:length]

    def _init_exfat(self,large):
        self.total=0x1010000 if large else 32768;self.csize=256 if large else 8
        self.reserved=24;self.fatsize=((self.total//self.csize+2)*4+511)//512
        self.data=((self.reserved+self.fatsize+127)//128)*128;self.ncl=(self.total-self.data)//self.csize
        self.initial={};self.fat=bytearray(self.fatsize*512);self.allocated={2}
        self.payload=bytes((i*37+11)&255 for i in range(1100));self.nested=bytes(range(256))
        self.setfat(0,0xfffffff8);self.setfat(1,self.eof);self.setfat(2,self.eof)
        # Build an independent compressed Unicode up-case table.
        table=bytearray();unit=0
        while unit<65536:
            end=unit
            while end<65536 and upper_unit(end)==end: end+=1
            if end-unit>=3:
                run=min(end-unit,65535);table+=struct.pack('<HH',65535,run);unit+=run
            else:
                table+=struct.pack('<H',upper_unit(unit));unit+=1
        self.bitmap_clusters=list(range(3,3+(self.ncl+8*self.csize*512-1)//(8*self.csize*512)))
        case_first=self.bitmap_clusters[-1]+1
        case_clusters=list(range(case_first,case_first+(len(table)+self.csize*512-1)//(self.csize*512)))
        for chain in (self.bitmap_clusters,case_clusters):
            self.allocated.update(chain)
            for a,b in zip(chain,chain[1:]+[self.eof]):self.setfat(a,b)
        for i in range((len(table)+511)//512):self.initial[self.clustersector(case_first)+i]=table[i*512:(i+1)*512].ljust(512,b'\0')
        root=bytearray(512);root[0]=0x81;u32(root,20,3);u64(root,24,(self.ncl+7)//8)
        root[32]=0x82;u32(root,36,checksum(table,32));u32(root,52,case_first);u64(root,56,len(table))
        self.initial[self.rootsector]=bytes(root);self._root_clusters=[2]
        self.file_chain=[32];self.subcluster=34;self.nestcluster=37
        self.add_exfat_file('HELLO.TXT',self.payload,self.file_chain)
        self.add_exfat_file('SUBDIR',exfat_entry('NESTED.BIN',37,len(self.nested),contiguous=True),[34],directory=True)
        self.allocated.add(37);self.initial[self.clustersector(37)]=self.nested+bytes(256)
        self._sync_exfat()
        if large:
            self.large_size=(1<<32)+64;self.large_offset=(1<<32)-16
            self.large_payload=bytes((i*19+3)&255 for i in range(80))
            count=(self.large_size+self.csize*512-1)//(self.csize*512)
            self.add_exfat_file('BIG.BIN',b'',list(range(100,100+count)),length=self.large_size,contiguous=True)
            for i,byte in enumerate(self.large_payload,self.large_offset):
                sector=self.clustersector(100)+i//512
                content=bytearray(self.initial.get(sector,bytes(512)));content[i%512]=byte;self.initial[sector]=bytes(content)
        boot=bytearray(512);boot[:11]=b'\xeb\x76\x90EXFAT   '
        u64(boot,64,self.prefix);u64(boot,72,self.total);u32(boot,80,self.reserved);u32(boot,84,self.fatsize)
        u32(boot,88,self.data);u32(boot,92,self.ncl);u32(boot,96,2);u32(boot,100,0x707)
        u16(boot,104,0x100);boot[108]=9;boot[109]=8 if large else 3;boot[110]=1;boot[111]=0x80;boot[112]=0xff
        boot[510:]=b'\x55\xaa';region=bytearray(boot)
        for _ in range(8):
            sector=bytearray(512);u32(sector,508,0xaa550000);region+=sector
        region+=bytes(1024)
        region+=struct.pack('<I',checksum(region,32,skip=(106,107,112)))*128
        for copy in (0,12):
            for i in range(12):self.initial[self.prefix+copy+i]=bytes(region[i*512:(i+1)*512])
        if self.prefix:
            mbr=bytearray(512);mbr[446]=0x80;mbr[450]=7
            u32(mbr,454,self.prefix);u32(mbr,458,self.total);mbr[510:]=b'\x55\xaa';self.initial[0]=bytes(mbr)

    def _sync_exfat(self):
        for i in range(self.fatsize):self.initial[self.prefix+self.reserved+i]=bytes(self.fat[i*512:(i+1)*512])
        bitmap=bytearray((self.ncl+7)//8)
        for c in self.allocated:bitmap[(c-2)//8]|=1<<((c-2)%8)
        for i in range((len(bitmap)+511)//512):self.initial[self.clustersector(3)+i]=bytes(bitmap[i*512:(i+1)*512]).ljust(512,b'\0')

    def add_exfat_file(self,name,data,chain=None,directory=False,length=None,contiguous=False):
        size=len(data) if length is None else length;clusterbytes=self.csize*512
        if chain is None:
            count=(size+clusterbytes-1)//clusterbytes;first=max(self.allocated)+2
            chain=list(range(first,first+2*count,2))
        self.allocated.update(chain)
        if not contiguous:
            for a,b in zip(chain,chain[1:]+[self.eof]):self.setfat(a,b)
        if directory:size=clusterbytes
        row=exfat_entry(name,chain[0] if chain else 0,size,16 if directory else 32,contiguous)
        root=bytearray(b''.join(self.initial.get(self.clustersector(c)+i,bytes(512)) for c in self._root_clusters for i in range(self.csize)))
        pos=next((i for i in range(0,len(root),32) if not root[i]),len(root))
        while pos+len(row)+32>len(root):
            c=max(self.allocated)+1;self.allocated.add(c);self._root_clusters.append(c);root+=bytes(clusterbytes)
        root[pos:pos+len(row)]=row
        for a,b in zip(self._root_clusters,self._root_clusters[1:]+[self.eof]):self.setfat(a,b)
        for i in range((pos+len(row)+511)//512):
            c=self._root_clusters[i//self.csize];self.initial[self.clustersector(c)+i%self.csize]=bytes(root[i*512:(i+1)*512])
        for i in range((len(data)+511)//512):
            c=chain[i//self.csize];self.initial[self.clustersector(c)+i%self.csize]=data[i*512:(i+1)*512].ljust(512,b'\0')
        self._sync_exfat()

    def _exfat_entries(self,model):
        data=b''.join(model.storage.get(self.clustersector(c)+i,bytes(512)) for c in self.chain(model,2) for i in range(self.csize))
        names={};self._exfat_chains={};pos=0
        while pos<len(data):
            if data[pos]==0:break
            if data[pos]!=0x85:pos+=32;continue
            count=data[pos+1]+1;block=data[pos:pos+count*32];pos+=count*32
            assert checksum(block,skip=(2,3))==struct.unpack_from('<H',block,2)[0],'exFAT entry checksum'
            assert block[32]==0xc0 and all(block[i]==0xc1 for i in range(64,len(block),32))
            encoded=b''.join(block[i+2:i+32] for i in range(64,len(block),32))[:block[35]*2];name=encoded.decode('utf-16-le')
            uppercase=b''.join(struct.pack('<H',upper_unit(unit)) for (unit,) in struct.iter_unpack('<H',encoded))
            assert checksum(uppercase)==struct.unpack_from('<H',block,36)[0],'exFAT name hash'
            first=struct.unpack_from('<I',block,52)[0];length=struct.unpack_from('<Q',block,56)[0]
            assert struct.unpack_from('<Q',block,40)[0]<=length
            attr=struct.unpack_from('<H',block,4)[0];names[name]=(first,0 if attr&16 else length,attr)
            clusters=(length+self.csize*512-1)//(self.csize*512)
            self._exfat_chains[name]=list(range(first,first+clusters)) if block[33]&2 else self.chain(model,first) if first else []
        return names

class FileImage(Image):
    """Add empty and fragmented text files without changing stage 6 fixtures."""
    def __init__(self,kind,prefix=0):
        super().__init__(kind,prefix)
        self.text=b'PtrocOS file commands\r\n'*30
        if kind==64:
            self.add_exfat_file('EMPTY.TXT',b'')
            self.add_exfat_file('TEXT.TXT',self.text,[40]);return
        self.setfat(10,12);self.setfat(12,self.eof)
        if kind==32:
            for sector in (prefix+1,prefix+7):
                info=bytearray(self.initial[sector]);u32(info,488,self.total-self.data-8);u32(info,492,13)
                self.initial[sector]=bytes(info)
        for copy in range(2):
            for i in range(self.fatsize):
                self.initial[prefix+self.reserved+copy*self.fatsize+i]=bytes(self.fat[i*512:(i+1)*512])
        root=bytearray(self.initial[self.rootsector])
        root[64:96]=entry(b'EMPTY   TXT',0,0)
        root[96:128]=entry(b'TEXT    TXT',10,len(self.text))
        self.initial[self.rootsector]=bytes(root)
        for i,cluster in enumerate((10,12)):
            self.initial[self.clustersector(cluster)]=self.text[i*512:(i+1)*512].ljust(512,b'\0')
