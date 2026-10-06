"""Independent literal FAT fixtures shared by native and pin-level tests."""
import struct

def u16(data,offset,value): struct.pack_into('<H',data,offset,value)
def u32(data,offset,value): struct.pack_into('<I',data,offset,value)
def entry(name,cluster,size,attribute=32):
    data=bytearray(32);data[:11]=name;data[11]=attribute
    u16(data,20,cluster>>16);u16(data,26,cluster&65535);u32(data,28,size)
    return data

class Image:
    def __init__(self,kind,prefix=0):
        self.kind,self.prefix=kind,prefix
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
    def eof(self): return {12:0xfff,16:0xffff,32:0x0fffffff}[self.kind]
    @property
    def rootsector(self):
        return self.clustersector(2) if self.kind==32 else self.prefix+self.reserved+2*self.fatsize
    def clustersector(self,cluster): return self.prefix+self.data+cluster-2
    def setfat(self,cluster,value):
        if self.kind==12:
            offset=cluster*3//2;old=int.from_bytes(self.fat[offset:offset+2],'little')
            new=(old&0xf)|(value<<4) if cluster&1 else (old&0xf000)|value
            self.fat[offset:offset+2]=new.to_bytes(2,'little')
        elif self.kind==16: u16(self.fat,cluster*2,value)
        else: u32(self.fat,cluster*4,value)
    def fatbytes(self,model,copy=0):
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
            else: cluster=struct.unpack_from('<I',table,cluster*4)[0]&0x0fffffff
        return result
    def root_entries(self,model):
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
        return b''.join(model.storage.get(self.clustersector(c),bytes(512)) for c in self.chain(model,first))[:length]
