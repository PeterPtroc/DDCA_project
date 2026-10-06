"""Sparse byte images for the independent SD SPI pin model."""
from pathlib import Path
from fatfs_fixture import Image
ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'build/ptrocos_storage';out.mkdir(parents=True,exist_ok=True)
def crc(data):
    value=0xffff
    for byte in data:
        value^=byte
        for _ in range(8): value=(value>>1)^(0xa001 if value&1 else 0)
    return value
for kind in (12,16):
    image=Image(kind)
    with (out/f'fat{kind}.hex').open('w',newline='\n') as file:
        for sector,data in sorted(image.initial.items()):
            file.write(f'@{sector*512:08x}\n')
            file.write('\n'.join(f'{byte:02x}' for byte in data)+'\n')
    print(f'FAT IMAGE PASS kind={kind} HELLO.TXT bytes={len(image.payload)} crc={crc(image.payload):04x} nested={crc(image.nested):04x}')
