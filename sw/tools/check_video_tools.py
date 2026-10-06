"""Exercise actual converter/FFmpeg paths, audio and silence, output protection."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
from convert_ptrocos_video import convert,digest

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/ptrocos_video/host-fixtures';OUT.mkdir(parents=True,exist_ok=True)
ffmpeg=shutil.which('ffmpeg.exe') or shutil.which('ffmpeg');ffprobe=shutil.which('ffprobe.exe') or shutil.which('ffprobe')
assert ffmpeg and ffprobe,'Install FFmpeg or add existing executable to PATH'
checks=0
for audio in [False,True]:
    source=OUT/('sound.mkv' if audio else 'silent.mkv')
    command=[ffmpeg,'-nostdin','-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=184x120:rate=17:duration=1.2']
    if audio:command+=['-f','lavfi','-i','sine=frequency=997:sample_rate=44100:duration=1.2']
    command+=['-threads','2','-c:v','ffv1']
    if audio:command+=['-c:a','pcm_s16le']
    command+=[str(source)];subprocess.run(command,check=True)
    for silent in ([False,True] if audio else [False]):
        output=source.with_name(source.stem+('-mute' if silent else '')+'.PTV')
        result=convert(source,output,15,11025,128,silent,ffmpeg,ffprobe,True)
        assert result['frames']>10 and result['audio_rate']==(11025 if audio and not silent else 0)
        subprocess.run([sys.executable,str(ROOT/'sw/tools/check_video_conversion.py'),str(output),'--ffmpeg',ffmpeg],check=True)
        before=digest(output)
        try:convert(source,output,ffmpeg=ffmpeg,ffprobe=ffprobe)
        except FileExistsError:pass
        else:raise AssertionError('Existing output replaced without force')
        assert digest(output)==before;checks+=1
source=OUT/'sound.mkv'
for fps,rate,threshold in [(9,8000,128),(31,8000,128),(15,7999,128),(15,16001,128),(15,8000,-1),(15,8000,256)]:
    try:convert(source,OUT/'invalid.PTV',fps,rate,threshold,ffmpeg=ffmpeg,ffprobe=ffprobe)
    except ValueError:pass
    else:raise AssertionError('Invalid configuration accepted')
    checks+=1
try:convert(source,source,ffmpeg=ffmpeg,ffprobe=ffprobe,force=True)
except ValueError:pass
else:raise AssertionError('Input overwritten')
checks+=1
assert not list(OUT.glob('.ptv-work-*'))
print(f'PTV HOST TOOLS PASS checks={checks} real-FFmpeg sound silent aspect-ratio fractional-rate atomic-output',flush=True)
