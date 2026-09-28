#!/usr/bin/env python3
"""Small two-pass assembler for the RV32I/custom subset used by the MVP."""
import argparse, re
REG={"zero":0,"ra":1,"sp":2,"gp":3,"tp":4,"t0":5,"t1":6,"t2":7,**{f"s{i}":8+i for i in range(2)},**{f"a{i}":10+i for i in range(8)},"s2":18,"s3":19,"s4":20,"s5":21,"s6":22,"s7":23,"s8":24,"s9":25,"s10":26,"s11":27,"t3":28,"t4":29,"t5":30,"t6":31}
REG.update({f"x{i}":i for i in range(32)})
def reg(s): return REG[s.lower()]
def num(s, labels, pc):
    if s == '.': return 0
    return labels[s] - pc if s in labels else int(s,0)
def enc_r(f7,rs2,rs1,f3,rd,op=0x33): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def assemble(lines):
    labels={}; pc=0; clean=[]
    for raw in lines:
        s=raw.split('#',1)[0].strip()
        while ':' in s:
            lab,s=s.split(':',1); labels[lab.strip()]=pc; s=s.strip()
        if s: clean.append((pc,s)); pc += 4 if not s.startswith('.word') else 4
    out=[]
    for pc,s in clean:
        p=[x for x in re.split(r'[ ,()]+',s) if x]; m=p[0].lower(); v=0
        if m=='.word': v=int(p[1],0)
        elif m in ('nop','mv'): v=(0x13)|(0<<7)|((0 if m=='nop' else reg(p[1]))<<7)|((0 if m=='nop' else reg(p[2]))<<15)
        elif m in ('add','sub','sll','slt','sltu','xor','srl','sra','or','and'):
            f3={'add':0,'sub':0,'sll':1,'slt':2,'sltu':3,'xor':4,'srl':5,'sra':5,'or':6,'and':7}[m]; f7=0x20 if m in ('sub','sra') else 0; v=enc_r(f7,reg(p[3]),reg(p[2]),f3,reg(p[1]))
        elif m in ('addi','slti','sltiu','xori','ori','andi','slli','srli','srai'):
            f3={'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7,'slli':1,'srli':5,'srai':5}[m]; imm=int(p[3],0); imm|=(0x400 if m=='srai' else 0); v=((imm&0xfff)<<20)|(reg(p[2])<<15)|(f3<<12)|(reg(p[1])<<7)|0x13
        elif m in ('lw','sw'):
            imm=int(p[2],0); rs1=reg(p[3]); rd=reg(p[1]); v=(((imm&0xfff)<<20)|(rs1<<15)|(2<<12)|(rd<<7)|3) if m=='lw' else ((((imm>>5)&0x7f)<<25)|(rd<<20)|(rs1<<15)|(2<<12)|((imm&0x1f)<<7)|0x23)
        elif m in ('lui','auipc'): v=((int(p[2],0)&0xfffff)<<12)|(reg(p[1])<<7)|(0x37 if m=='lui' else 0x17)
        elif m in ('beq','bne','blt','bge','bltu','bgeu'):
            imm=num(p[3],labels,pc); f3={'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}[m]; v=(((imm>>12)&1)<<31)|(((imm>>5)&0x3f)<<25)|(reg(p[2])<<20)|(reg(p[1])<<15)|(f3<<12)|(((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|0x63
        elif m in ('jal','j','call'): rd=0 if m=='j' else (1 if m=='call' else reg(p[1])); target=p[1] if m!='jal' else p[2]; imm=num(target,labels,pc); v=(((imm>>20)&1)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xff)<<12)|(rd<<7)|0x6f
        elif m=='ret': v=(1<<15)|(0<<12)|(0<<7)|0x67
        elif m=='jalr': v=(int(p[3],0)&0xfff)<<20|(reg(p[2])<<15)|(reg(p[1])<<7)|0x67
        elif m=='crc16.b': v=reg(p[3])<<20|reg(p[2])<<15|reg(p[1])<<7|0x0b
        else: raise ValueError(f"unsupported instruction: {s}")
        out.append(v&0xffffffff)
    return out
if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('input'); ap.add_argument('output'); a=ap.parse_args()
    with open(a.input) as f: words=assemble(f.readlines())
    with open(a.output,'w') as f: f.write('\n'.join(f'{w:08x}' for w in words)+'\n')
