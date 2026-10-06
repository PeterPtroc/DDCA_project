"""Run the production C driver against an independent byte-level SPI card model."""
import binascii
from collections import deque
import ctypes as C
from pathlib import Path
import random
import subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/ptrocos_sd';OUT.mkdir(parents=True,exist_ok=True)
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
                str(ROOT/'sw/ptrocos/storage/sd_card.c'),'-o',str(OUT/'sd_card.dll')],check=True)
lib=C.CDLL(str(OUT/'sd_card.dll'))
TRANSFER=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_uint8)
SWITCH=C.CFUNCTYPE(None,C.c_void_p,C.c_int)
SPEED=C.CFUNCTYPE(None,C.c_void_p,C.c_uint32)
FLAG=C.CFUNCTYPE(C.c_int,C.c_void_p)
TIME=C.CFUNCTYPE(C.c_uint32,C.c_void_p)
PAUSE=C.CFUNCTYPE(None,C.c_void_p,C.c_uint32)
class Transport(C.Structure):
    _fields_=[('transfer',TRANSFER),('select',SWITCH),('power',SWITCH),('speed',SPEED),
              ('present',FLAG),('milliseconds',TIME),('pause',PAUSE),('cancelled',FLAG),('context',C.c_void_p)]
class Card(C.Structure):
    _fields_=[('bus',Transport)]+[(n,C.c_uint32) for n in 'sectors ocr completed reads writes'.split()]+[
        ('initialized',C.c_uint8),('high_capacity',C.c_uint8),('csd',C.c_uint8*16),('cid',C.c_uint8*16),('last_error',C.c_int)]
lib.sd_card_setup.argtypes=[C.POINTER(Card),C.POINTER(Transport)]
lib.sd_card_initialize.argtypes=[C.POINTER(Card)];lib.sd_card_ready.argtypes=[C.POINTER(Card)]
for name in ('sd_card_read','sd_card_write'):
    getattr(lib,name).argtypes=[C.POINTER(Card),C.c_uint32,C.c_void_p,C.c_uint32]
lib.sd_card_sync.argtypes=[C.POINTER(Card)]
lib.sd_crc7.argtypes=[C.c_void_p,C.c_size_t];lib.sd_crc7.restype=C.c_uint8
lib.sd_crc16.argtypes=[C.c_void_p,C.c_size_t];lib.sd_crc16.restype=C.c_uint16

def crc7(data):
    # Polynomial division of the whole bit string, independent of C's feedback loop.
    dividend=int.from_bytes(data,'big')<<7
    while dividend.bit_length()>=8: dividend^=0x89<<(dividend.bit_length()-8)
    return dividend

checks=0
class Model:
    def __init__(self,version=2,high=True):
        self.version,self.high=version,high;self.sectors=32768
        self.storage={};self.powered=False;self.selected=False;self.attached=True
        self.us=0;self.hz=400000;self.transfers=0;self.startup=0;self.cancel=False
        self.exception=None;self.remove_at=self.fail_at=self.cancel_at=None
        self.never_init=self.bad_echo=self.bad_voltage=self.bad_csd=False
        self.read_crc_bad=self.read_token_bad=self.read_timeout=False
        self.write_reject=self.write_crc_reject=self.busy_forever=self.hold_after_write=False
        self.commands=[];self.reset()
        def safe_transfer(ctx,byte):
            try: return self.exchange(byte)
            except Exception as error: self.exception=error;return -1
        self.callbacks=(TRANSFER(safe_transfer),SWITCH(lambda ctx,on:self.choose(on)),
            SWITCH(lambda ctx,on:self.power(on)),SPEED(lambda ctx,hz:setattr(self,'hz',hz)),
            FLAG(lambda ctx:int(self.attached)),TIME(lambda ctx:(self.us//1000)&0xffffffff),
            PAUSE(lambda ctx,ms:setattr(self,'us',self.us+ms*1000)),FLAG(lambda ctx:int(self.cancel)))
        self.bus=Transport(*self.callbacks,None);self.card=Card()
        lib.sd_card_setup(C.byref(self.card),C.byref(self.bus))
    def reset(self):
        self.queue=deque();self.frame=[];self.write_data=None;self.write_target=None
        self.write_token=False;self.idle=True;self.app=False;self.init_tries=0
        self.crc_enabled=False;self.busy=0
    def power(self,on):
        self.powered=bool(on)
        if not on: self.reset();self.startup=0
    def choose(self,on):
        self.selected=bool(on)
        if not on: self.queue.clear();self.frame=[];self.write_data=None;self.write_token=False
    def packet(self,data):
        crc=binascii.crc_hqx(data,0)
        if self.read_crc_bad: crc^=1;self.read_crc_bad=False
        return [255,255,0xfe,*data,crc>>8,crc&255]
    def address(self,arg):
        if not self.high: assert arg%512==0;arg//=512
        assert arg<self.sectors
        return arg
    def exchange(self,byte):
        self.transfers+=1;self.us+=(8_000_000+self.hz-1)//self.hz
        if self.remove_at==self.transfers: self.attached=False;return -1
        if self.cancel_at==self.transfers: self.cancel=True
        if self.fail_at==self.transfers: return -1
        assert self.attached and self.powered
        if not self.selected:
            assert byte==255
            self.startup+=8;return 255
        if self.queue:
            assert byte==255
            return self.queue.popleft()
        if self.busy_forever or self.busy:
            if self.busy: self.busy-=1
            return 0
        if self.write_data is not None:
            self.write_data.append(byte)
            if len(self.write_data)==514:
                data=bytes(self.write_data[:512]);crc=(self.write_data[512]<<8)|self.write_data[513]
                assert crc==binascii.crc_hqx(data,0) and self.crc_enabled
                token=11 if self.write_crc_reject else 13 if self.write_reject else 5
                if token==5:
                    self.storage[self.write_target]=data
                    if self.hold_after_write: self.busy_forever=True
                self.queue.append(token);self.busy=3;self.write_data=None
            return 255
        if self.write_token:
            if byte==255: return 255
            assert byte==0xfe
            self.write_token=False;self.write_data=[];return 255
        if not self.frame:
            if byte==255: return 255
            assert byte&0xc0==0x40
        self.frame.append(byte)
        if len(self.frame)<6: return 255
        packet=bytes(self.frame);self.frame=[]
        assert packet[5]==(crc7(packet[:5])<<1)|1, f'Command CRC: {packet.hex()}'
        cmd=packet[0]&63;arg=int.from_bytes(packet[1:5],'big');self.commands.append((cmd,arg))
        trailing=[]
        if cmd==0:
            assert self.startup>=74 and self.hz<=400000
            self.idle=True;self.crc_enabled=False;response=1
        elif cmd==8:
            assert arg==0x1aa
            response=1 if self.version==2 else 5
            if self.version==2: trailing=list((0x1ab if self.bad_echo else 0x1aa).to_bytes(4,'big'))
        elif cmd==55: self.app=True;response=int(self.idle)
        elif cmd==41:
            assert self.app and arg==(0x40000000 if self.version==2 else 0)
            self.app=False;self.init_tries+=1
            if self.init_tries>=3 and not self.never_init: self.idle=False
            response=int(self.idle)
        elif cmd==58:
            response=0;ocr=(0xc0000000 if self.high else 0x80000000)|(0 if self.bad_voltage else 0x00ff8000)
            trailing=list(ocr.to_bytes(4,'big'))
        elif cmd==59: assert arg==1;self.crc_enabled=True;response=0
        elif cmd==16: assert not self.high and arg==512;response=0
        elif cmd==9:
            csd=bytearray(16)
            if self.high:
                size=self.sectors//1024-1;csd[0]=0x40;csd[7]=(size>>16)&63;csd[8]=(size>>8)&255;csd[9]=size&255
            else:
                csd[5]=9;csd[6]=3;csd[7]=255;csd[8]=0xc0;csd[10]=0x80
            if self.bad_csd: csd[0]=0x80
            csd[15]=(crc7(csd[:15])<<1)|1
            response=0;trailing=self.packet(csd)
        elif cmd==10:
            cid=bytearray(b'\x01PTSDCARD01\x01\x02\x03\x04\x01');assert len(cid)==16
            cid[15]=(crc7(cid[:15])<<1)|1
            response=0;trailing=self.packet(cid)
        elif cmd==17:
            sector=self.address(arg);response=0
            if self.read_token_bad: trailing=[255,8];self.read_token_bad=False
            elif self.read_timeout: trailing=[255]*65536
            else: trailing=self.packet(self.storage.get(sector,bytes(512)))
        elif cmd==24:
            self.write_target=self.address(arg);self.write_token=True;response=0
        else: raise AssertionError(f'Unexpected CMD{cmd}')
        self.queue.extend([255,255,255,response,*trailing]);return 255
    def call(self,function,*args,expected=0):
        global checks
        result=getattr(lib,function)(C.byref(self.card),*args)
        if self.exception: raise self.exception
        assert result==expected,(function,result,expected,self.card.last_error)
        assert not self.selected,f'CS held after {function}'
        checks+=1;return result
    def init(self):
        self.call('sd_card_initialize')
        assert self.card.initialized and self.card.sectors==self.sectors and self.card.high_capacity==self.high
        assert self.card.ocr&0x80000000 and self.crc_enabled
        assert self.hz==12500000

for payload,known in ((bytes.fromhex('4000000000'),0x4a),(bytes.fromhex('48000001aa'),0x43)):
    assert crc7(payload)==known and lib.sd_crc7(payload,len(payload))==known
assert lib.sd_crc16(bytes([255])*512,512)==0x7fa1
rng=random.Random(0x53444336)
for size in (0,1,5,16,512,1024):
    data=bytes(rng.randrange(256) for _ in range(size))
    assert lib.sd_crc7(data,len(data))==crc7(data)
    assert lib.sd_crc16(data,len(data))==binascii.crc_hqx(data,0)

for version,high in ((1,False),(2,False),(2,True)):
    model=Model(version,high);model.init()
    assert any(cmd==16 for cmd,arg in model.commands)==(not high)
    for sector,count in ((0,1),(7,3),(model.sectors-2,2)):
        data=bytes(rng.randrange(256) for _ in range(count*512))
        buffer=C.create_string_buffer(data);read=C.create_string_buffer(count*512)
        model.call('sd_card_write',sector,buffer,count);assert model.card.completed==count
        model.call('sd_card_read',sector,read,count);assert model.card.completed==count and read.raw==data
    assert model.card.reads==model.card.writes==6
    command_count=len(model.commands)
    buffer=C.create_string_buffer(512)
    for sector,count in ((model.sectors,1),(model.sectors-1,2),(0xffffffff,0xffffffff),(0,0)):
        model.call('sd_card_read',sector,buffer,count,expected=5)
        assert model.card.initialized and model.card.completed==0
    model.call('sd_card_write',0,None,1,expected=5)
    assert len(model.commands)==command_count
    model.call('sd_card_sync')
    model.attached=False;model.call('sd_card_read',0,buffer,1,expected=1)
    assert not model.card.initialized
    model.attached=True;model.init();model.call('sd_card_read',7,buffer,1)

for fault,error in (('bad_echo',3),('bad_voltage',3),('bad_csd',3),('never_init',2)):
    model=Model();setattr(model,fault,True);model.call('sd_card_initialize',expected=error)
    assert not model.card.initialized and model.card.sectors==0
    setattr(model,fault,False);model.init()
for fault,error in (('read_crc_bad',4),('read_token_bad',3),('read_timeout',2),('write_crc_reject',4),('write_reject',9)):
    model=Model();model.init();setattr(model,fault,True);buffer=C.create_string_buffer(bytes([42])*512)
    function='sd_card_write' if fault.startswith('write') else 'sd_card_read'
    model.call(function,4,buffer,1,expected=error)
    assert not model.card.initialized and model.card.completed==0
    setattr(model,fault,False);model.init();model.call('sd_card_read',4,buffer,1)
for injection,error in (('remove_at',1),('cancel_at',8),('fail_at',7)):
    for function in ('sd_card_read','sd_card_write'):
        model=Model();model.init();setattr(model,injection,model.transfers+100)
        buffer=C.create_string_buffer(bytes([77])*1024)
        model.call(function,5,buffer,2,expected=error)
        assert not model.card.initialized and model.card.completed==0
        model.attached=True;model.cancel=False;setattr(model,injection,None)
        model.init();model.call('sd_card_read',5,buffer,1)
model=Model();model.init();model.busy_forever=True
model.call('sd_card_sync',expected=2);assert not model.card.initialized
model.busy_forever=False;model.init()
for injection,error in (('remove_at',1),('cancel_at',8),('fail_at',7)):
    for function in ('sd_card_read','sd_card_write'):
        model=Model();model.init();setattr(model,injection,model.transfers+600)
        payload=bytes([91])*1024;buffer=C.create_string_buffer(payload)
        model.call(function,5,buffer,2,expected=error)
        assert not model.card.initialized and model.card.completed==1
        if function=='sd_card_write': assert model.storage[5]==payload[:512]
        model.attached=True;model.cancel=False;setattr(model,injection,None)
        model.init();model.call('sd_card_read',5,buffer,1)
model=Model();model.us=(0xffffffff-4)*1000;model.init()
assert model.us//1000>0xffffffff # Initialization spans the 32-bit timer wrap.
model=Model();model.sectors=1<<32;model.call('sd_card_initialize',expected=5)
assert not model.card.initialized and not model.card.sectors
model=Model();model.init();model.hold_after_write=True
payload=bytes([83])*512;buffer=C.create_string_buffer(payload)
model.call('sd_card_write',5,buffer,1,expected=2)
assert not model.card.initialized and model.card.completed==0 and model.storage[5]==payload
# A timeout after card acceptance cannot imply that no bytes reached the card.
model.hold_after_write=model.busy_forever=False;model.init()
print(f'SD CARD C PASS checks={checks} SDSC-v1 SDSC-v2 SDHC read-write CRC7 CRC16 bounds removal cancel timeout faults recovery')
