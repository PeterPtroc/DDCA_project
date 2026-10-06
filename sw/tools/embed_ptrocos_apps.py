from pathlib import Path
import struct
out=Path('build/ptrocos_elf/apps.h')
rows=['// Generated from the actual stripped RV32IM ELF applications.']
for name in ('hello','fault','loop'):
    path=Path(f'build/ptrocos_elf/apps/{name}.elf')
    data=bytearray(path.read_bytes())
    # Section tables are optional for ET_EXEC. Retain the exact program-header
    # payloads and instructions; remove unused section/debug metadata from the
    # delivered small applications and their diagnostic ROM copies.
    table=struct.unpack_from('<I',data,28)[0]
    count=struct.unpack_from('<H',data,44)[0]
    spans=[table+32*count]
    for i in range(count):
        row=struct.unpack_from('<8I',data,table+i*32)
        spans.append(row[1]+row[4])
    end=max(spans)
    struct.pack_into('<I',data,32,0)
    struct.pack_into('<HHH',data,46,0,0,0)
    data=data[:end]
    path.write_bytes(data)
    rows.append(f'static const unsigned char app_{name}[]={{')
    rows.extend(','.join(f'0x{x:02x}' for x in data[i:i+24])+',' for i in range(0,len(data),24))
    rows.append('};')
    print(f'{name}: {len(data)} ELF bytes')
out.write_text('\n'.join(rows)+'\n',encoding='utf-8')
