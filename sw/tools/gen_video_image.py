from pathlib import Path
from video_fixture import VideoImage
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/ptrocos_video';OUT.mkdir(parents=True,exist_ok=True)
fixture=VideoImage(frames=8,fps=30);rows=[]
for sector,data in sorted(fixture.initial.items()):
    rows.append(f'@{sector*512:x}')
    rows.extend(' '.join(f'{b:02x}' for b in data[i:i+32]) for i in range(0,512,32))
(OUT/'video-fat16.hex').write_text('\n'.join(rows)+'\n',encoding='ascii')
for frame,picture in enumerate(fixture.pictures):
    words=[]
    for y in range(120):
        row=bytes(sum(picture[y][x+b]<<b for b in range(8)) for x in range(0,160,8))+b'\0'*12
        words.extend(f'{int.from_bytes(row[n:n+16],"little"):032x}' for n in [0,16])
    (OUT/f'clip.{frame}.words.hex').write_text('\n'.join(words)+'\n',encoding='ascii')
(OUT/'clip.pcm.hex').write_text('\n'.join(f'{v:04x}' for v in fixture.samples)+'\n',encoding='ascii')
print('PTV PIN FIXTURE PASS fragmented FAT16 CLIP=8frames/30fps/8000Hz SILENT=5frames/30fps samples=2133')
