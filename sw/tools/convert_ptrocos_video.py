"""Convert a local video into bounded, interleaved PTV1 monochrome/PCM packets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()

def convert(source, output, fps=15, rate=16000, threshold=128, silent=False,
            ffmpeg='ffmpeg', ffprobe='ffprobe', force=False):
    source=Path(source).resolve();output=Path(output).resolve()
    if not source.is_file(): raise ValueError('Input video does not exist')
    if source==output: raise ValueError('Input and output must differ')
    if not 10<=fps<=30 or not 8000<=rate<=16000 or not 0<=threshold<=255:
        raise ValueError('fps=10..30, audio rate=8000..16000, threshold=0..255')
    if output.exists() and not force: raise FileExistsError(output)
    output.parent.mkdir(parents=True,exist_ok=True)
    probe=json.loads(subprocess.check_output([ffprobe,'-v','error','-show_streams','-show_format','-of','json',str(source)]))
    if not any(s['codec_type']=='video' for s in probe['streams']): raise ValueError('No video stream')
    rate=rate if not silent and any(s['codec_type']=='audio' for s in probe['streams']) else 0
    source_hash=digest(source)
    commands=[]
    with tempfile.TemporaryDirectory(prefix='.ptv-work-',dir=output.parent) as directory:
        temp=Path(directory).resolve();temp.relative_to(output.parent)
        gray=temp/'gray.raw';audio=temp/'audio.raw';packed=temp/'output.ptv'
        base=[ffmpeg,'-nostdin','-hide_banner','-loglevel','error','-threads','2','-filter_threads','2','-i',str(source)]
        filters=f'fps={fps},scale=160:120:flags=area:force_original_aspect_ratio=decrease,pad=160:120:(ow-iw)/2:(oh-ih)/2:black,format=gray'
        commands.append(base+['-map','0:v:0','-an','-vf',filters,'-vsync','0','-f','rawvideo',str(gray)])
        subprocess.run(commands[-1],check=True)
        count,remainder=divmod(gray.stat().st_size,160*120)
        if remainder or not count or count>fps*3600: raise ValueError('Empty, truncated or longer than one hour')
        if rate:
            commands.append(base+['-map','0:a:0','-vn','-ac','1','-ar',str(rate),'-c:a','pcm_u16le','-f','u16le',str(audio)])
            subprocess.run(commands[-1],check=True)
        else: audio.write_bytes(b'')
        required=count*rate//fps
        available=audio.stat().st_size//2
        header=struct.pack('<4sHHHHIIIII',b'PTV1',32,int(bool(rate)),160,120,fps,count,rate,2400,0)
        with gray.open('rb') as video,audio.open('rb') as sound,packed.open('xb') as destination:
            destination.write(header)
            for frame in range(count):
                levels=video.read(160*120);bits=bytearray(2400)
                if len(levels)!=160*120: raise ValueError('Raw frame truncated')
                for index,value in enumerate(levels):
                    if value>=threshold: bits[index>>3]|=1<<(index&7)
                destination.write(bits)
                samples=(frame+1)*rate//fps-frame*rate//fps
                data=sound.read(samples*2)
                if len(data)%2: raise ValueError('Raw PCM truncated')
                destination.write(data+b'\x00\x80'*(samples-len(data)//2))
        expected=32+count*2400+required*2
        if packed.stat().st_size!=expected: raise ValueError('Packed file length mismatch')
        if digest(source)!=source_hash: raise ValueError('Input changed during conversion')
        if output.exists() and not force: raise FileExistsError(output)
        os.replace(packed,output)
    result={'format':'PTV1','source':str(source),'source_sha256':source_hash,
        'output':str(output),'sha256':digest(output),'bytes':expected,'width':160,'height':120,
        'fps':fps,'frames':count,'duration_seconds':count/fps,'audio_rate':rate,
        'audio_samples':required,'audio_padded_samples':max(0,required-available),
        'audio_trimmed_samples':max(0,available-required),'threshold':threshold,
        'bit_order':'left pixel in bit0; little endian bytes','commands':commands,
        'ffmpeg_version':subprocess.check_output([ffmpeg,'-version'],text=True).splitlines()[0]}
    output.with_suffix(output.suffix+'.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--fps',type=int,default=15);p.add_argument('--audio-rate',type=int,default=16000)
    p.add_argument('--threshold',type=int,default=128);p.add_argument('--silent',action='store_true')
    p.add_argument('--force',action='store_true');p.add_argument('--ffmpeg',default=shutil.which('ffmpeg') or 'ffmpeg')
    p.add_argument('--ffprobe',default=shutil.which('ffprobe') or 'ffprobe')
    a=p.parse_args()
    result=convert(a.source,a.output,a.fps,a.audio_rate,a.threshold,a.silent,a.ffmpeg,a.ffprobe,a.force)
    print(f"PTV CONVERT PASS frames={result['frames']} fps={result['fps']} audio={result['audio_rate']} bytes={result['bytes']} SHA256={result['sha256']}",flush=True)
if __name__=='__main__': main()
