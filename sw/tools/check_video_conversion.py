"""Independently verify real-video PTV bits and interleaved PCM against FFmpeg."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import numpy as np

def main():
    p=argparse.ArgumentParser();p.add_argument('packed',type=Path)
    p.add_argument('--ffmpeg',default='ffmpeg');p.add_argument('--short',action='store_true');a=p.parse_args()
    meta=json.loads(a.packed.with_suffix(a.packed.suffix+'.json').read_text(encoding='utf-8'))
    source=Path(meta['source']);fps=meta['fps'];rate=meta['audio_rate'];threshold=meta['threshold']
    with source.open('rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()==meta['source_sha256']
    with a.packed.open('rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()==meta['sha256']
    frames=meta['frames'];checked=0;samples=0
    with tempfile.TemporaryDirectory(prefix='ptv-oracle-',dir=a.packed.parent) as directory:
        gray=Path(directory)/'gray.raw';audio=Path(directory)/'audio.raw'
        base=[a.ffmpeg,'-nostdin','-hide_banner','-loglevel','error','-threads','2','-filter_threads','2','-i',str(source)]
        filters=f'fps={fps},scale=160:120:flags=area:force_original_aspect_ratio=decrease,pad=160:120:(ow-iw)/2:(oh-ih)/2:black,format=gray'
        subprocess.run(base+['-map','0:v:0','-an','-vf',filters,'-vsync','0','-f','rawvideo',str(gray)],check=True)
        if rate:subprocess.run(base+['-map','0:a:0','-vn','-ac','1','-ar',str(rate),'-c:a','pcm_u16le','-f','u16le',str(audio)],check=True)
        else:audio.write_bytes(b'')
        with gray.open('rb') as video,audio.open('rb') as sound,a.packed.open('rb') as ptv:
            header=struct.unpack('<4sHHHHIIIII',ptv.read(32))
            assert header==(b'PTV1',32,int(bool(rate)),160,120,fps,frames,rate,2400,0)
            for frame in range(frames):
                levels=video.read(19200);bits=ptv.read(2400)
                assert len(levels)==19200 and len(bits)==2400
                unpacked=np.unpackbits(np.frombuffer(bits,dtype=np.uint8),bitorder='little')
                assert np.array_equal(unpacked,np.frombuffer(levels,dtype=np.uint8)>=threshold),frame
                amount=(frame+1)*rate//fps-frame*rate//fps
                wanted=sound.read(amount*2);wanted+=b'\x00\x80'*(amount-len(wanted)//2)
                actual=ptv.read(amount*2);assert actual==wanted,('PCM',frame)
                checked+=1;samples+=amount
                if a.short and frame>=30:break
            if not a.short:assert not ptv.read(1) and not video.read(1)
    result={'frames':checked,'pixels':checked*19200,'samples':samples,'sha256':meta['sha256'],
        'independent_bit_unpack':True,'full_file_verified':not a.short}
    a.packed.with_suffix(a.packed.suffix+'.verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(f"PTV CONVERSION VERIFY PASS frames={checked} pixels={result['pixels']} samples={samples}",flush=True)
if __name__=='__main__':main()
