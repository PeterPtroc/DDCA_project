#!/usr/bin/env python3
"""Generate the CRC-16/MODBUS lookup table used by software/tools."""
def update(crc, byte):
    crc ^= byte
    for _ in range(8):
        crc = (crc >> 1) ^ (0xA001 if crc & 1 else 0)
    return crc & 0xffff

if __name__ == "__main__":
    print("\n".join(f"{update(0, i):04x}" for i in range(256)))
