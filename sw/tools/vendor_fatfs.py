"""Reproduce the pinned FatFs source and apply its official patches strictly."""
import argparse
import hashlib
from pathlib import Path
import re
import zipfile

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--cache',type=Path,default=ROOT/'build/ptrocos_sd_research')
args=parser.parse_args()
expected={'ff16.zip':'99f7dc1f7e095356e4a9e3dbe29959090d8b948afe2bbc5441e52fdf4b85449e',
          'ff16p1.diff':'7996ddc3135f3d534a8153f7d75d587030e5c8551b003c3b7ee823ffb7fc64bf',
          'ff16p2.diff':'5cd39f1fc299f0f1dec9fa1ce544dc0bc048b2f6eb3b8161476ed20f9cf1e290'}
for name,digest in expected.items():
    if hashlib.sha256((args.cache/name).read_bytes()).hexdigest()!=digest:
        raise RuntimeError(f'Upstream hash mismatch: {name}')

def apply(text,diff):
    original=text.splitlines();patch=diff.splitlines();output=[];cursor=0;i=2
    while i<len(patch):
        if not patch[i]: i+=1;continue
        match=re.fullmatch(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@.*',patch[i])
        if not match: raise RuntimeError(f'Invalid patch hunk: {patch[i]}')
        start=int(match[1])-1;old_count=int(match[2] or 1);new_count=int(match[4] or 1)
        if start<cursor: raise RuntimeError('Overlapping patch hunks')
        output.extend(original[cursor:start]);cursor=start;i+=1;removed=added=0
        while removed<old_count or added<new_count:
            row=patch[i];i+=1
            if not row: row=' '
            kind,body=row[0],row[1:]
            if kind in (' ','-'):
                if original[cursor]!=body: raise RuntimeError(f'Patch context differs at source line {cursor+1}')
                cursor+=1;removed+=1
            if kind in (' ','+'): output.append(body);added+=1
            if kind not in (' ','-','+') or removed>old_count or added>new_count:
                raise RuntimeError('Invalid hunk line/count')
    output.extend(original[cursor:]);return '\n'.join(output)+'\n'

out=ROOT/'third_party/fatfs';(out/'upstream').mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(args.cache/'ff16.zip') as archive:
    for name in ('ff.c','ff.h','ffconf.h','diskio.h','ffunicode.c','ffsystem.c'):
        data=archive.read('source/'+name);(out/'upstream'/name).write_bytes(data)
        if name in ('ff.h','diskio.h','ffunicode.c'): (out/name).write_bytes(data)
    text=archive.read('source/ff.c').decode('utf-8-sig')
for name in ('ff16p1.diff','ff16p2.diff'):
    patch=(args.cache/name).read_bytes();(out/name).write_bytes(patch)
    text=apply(text,patch.decode())
(out/'ff.c').write_bytes(text.encode('utf-8'))
print('FATFS VENDOR PASS R0.16 + patch-1 + patch-2; upstream bytes preserved; strict context checks')
