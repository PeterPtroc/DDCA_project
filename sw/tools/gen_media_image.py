from pathlib import Path
from media_fixture import MediaImage
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/ptrocos_media';OUT.mkdir(parents=True,exist_ok=True)
fixture=MediaImage();rows=[]
for sector,data in sorted(fixture.initial.items()):
    rows.append(f'@{sector*512:x}')
    rows.extend(' '.join(f'{b:02x}' for b in data[i:i+32]) for i in range(0,512,32))
(OUT/'media-fat16.hex').write_text('\n'.join(rows)+'\n',encoding='ascii')
for name,pixels in [('image',fixture.pixels),('top',fixture.top_pixels)]:
    (OUT/(name+'.rgb.hex')).write_text('\n'.join(f'{((p>>12)&15)<<8 | ((p>>7)&15)<<4 | ((p>>1)&15):03x}' for row in pixels for p in row)+'\n',encoding='ascii')
for name,samples in [('sound',fixture.samples),('short',fixture.short_samples)]:
    (OUT/(name+'.pcm.hex')).write_text('\n'.join(f'{v:04x}' for v in samples)+'\n',encoding='ascii')
print('MEDIA FIXTURE PASS fragmented FAT16 BMP=321x9/24 bottom-up,3x5/32 top-down WAV=48000/16/stereo,8000/8/mono')
