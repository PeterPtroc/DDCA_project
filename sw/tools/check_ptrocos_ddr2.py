"""Host CRC oracle and UART acceptance for the compiled SoC diagnostic."""
from pathlib import Path
import re


def main():
    crc = 0xffff
    for index in range(256):
        word = ((index * 0x9e3779b9) & 0xffffffff) ^ 0xa55a1357
        for byte in word.to_bytes(4, 'little'):
            crc ^= byte
            for _ in range(8):
                crc = (crc >> 1) ^ (0xa001 if crc & 1 else 0)
    for style in range(2):
        text = Path(f'build/ptrocos_ddr2/uart.style{style}.log').read_text()
        values = re.findall(r'^DMA CRC ([0-9a-f]{8})$', text, re.M)
        assert len(values) == 2 and all(int(value, 16) == crc for value in values), (style, crc, values)
        assert text.count('PTROCOS DDR2 TEST\n') == 2, (style, text)
        assert text.count('DDR2 DMA PASS\n') == 2, (style, text)
        assert 'r=selftest f=full-128MiB-sweep\n' in text, (style, text)
        assert 'FAIL' not in text, (style, text)
    print(f'PTROCOS UART/CRC PASS: two runs per PC style, independent CRC=0x{crc:04x}')


if __name__ == '__main__':
    main()
