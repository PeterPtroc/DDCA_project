"""Independent pixel oracle for the pin-level RGB565 scanout test."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'build/ptrocos_graphics';out.mkdir(parents=True,exist_ok=True)
for width,height,name in ((32,12,'small'),(640,480,'full')):
    for choice,base in enumerate((0x81000ff0,0x81101000)):
        stride=width*2+16
        colours=[]
        for y in range(height):
            for x in range(width):
                offset=base-0x80000000+y*stride+x*2
                n=(offset>>1)^(offset>>19)
                red=((n*3+1)&31)>>1;green=((n*5+7)&63)>>2;blue=((n*7+3)&31)>>1
                colours.append(f'{red:x}{green:x}{blue:x}\n')
        (out/f'{name}.{choice}.rgb.hex').write_text(''.join(colours),encoding='ascii',newline='\n')
    print(f'GRAPHICS ORACLE PASS {name} pixels={width*height} RGB565 stride={width*2+16} 4K-edge two-front-buffers')
for choice in range(2):
    pixels=[]
    bars=(0xffff,0xffe0,0x07ff,0x07e0,0xf81f,0xf800,0x001f,0)
    for y in range(480):
        for x in range(640):
            if choice==0:
                value=bars[x//80]
            else:
                value=(((x//16)%32)<<11)|((y//8)<<5)|(((x^y)//16)%32)
            pixels.append(f'{((value>>12)&15):x}{((value>>7)&15):x}{((value>>1)&15):x}\n')
    (out/f'shell.{choice}.rgb.hex').write_text(''.join(pixels),encoding='ascii',newline='\n')
print('GRAPHICS SHELL ORACLE PASS two 640x480 RGB565 patterns')
