from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/ptrocos_video';OUT.mkdir(parents=True,exist_ok=True)
for frame in range(2):
    # Expected raster is computed from source coordinates, not unpacked DDR data.
    pixel=lambda x,y: ((x*5+y*7+frame*31)%256)>=128
    raster=['fff' if pixel(x//4,y//4) else '000' for y in range(480) for x in range(640)]
    words=[]
    for y in range(120):
        row=bytes(sum(int(pixel(byte*8+bit,y))<<bit for bit in range(8)) for byte in range(20))+b'\0'*12
        words.extend(f'{int.from_bytes(row[n:n+16],"little"):032x}' for n in [0,16])
    (OUT/f'mono.{frame}.rgb.hex').write_text('\n'.join(raster)+'\n',encoding='ascii')
    (OUT/f'mono.{frame}.words.hex').write_text('\n'.join(words)+'\n',encoding='ascii')
print('MONO FIXTURE PASS independent 160x120 bits and 640x480 raster')
