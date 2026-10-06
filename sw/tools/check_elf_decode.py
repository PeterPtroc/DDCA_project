"""Exercise the real C loader with independent ELF bytes and canary memory.

Checks complete prevalidation, every copied/zeroed byte, boundaries, and
read/cancel/output failures. This does not claim instruction execution.
"""
import ctypes as C
from pathlib import Path
import random
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/ptrocos_elf'
CODE, CODE_END, DATA, DATA_END = 0x10000, 0x14000, 0x80800000, 0x808ff000
READ = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint)
CANCEL = C.CFUNCTYPE(C.c_int, C.c_void_p)
WRITE = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint)
PROGRESS = C.CFUNCTYPE(None, C.c_void_p)

class Source(C.Structure):
    _fields_ = [('size', C.c_uint32), ('read', READ), ('cancelled', CANCEL), ('context', C.c_void_p)]
class Segment(C.Structure):
    _fields_ = [(name, C.c_uint32) for name in ('offset', 'address', 'file_bytes', 'memory_bytes', 'flags')]
class Image(C.Structure):
    _fields_ = [(name, C.c_uint32) for name in ('entry', 'count', 'file_bytes', 'memory_bytes', 'abi_version', 'loaded')] + [('segments', Segment * 8)]
class Sink(C.Structure):
    _fields_ = [('write', WRITE), ('progress', PROGRESS), ('context', C.c_void_p)]

def fixture(code_bytes=600, code_memory=950, data_bytes=513, data_memory=900,
            code_address=CODE, data_address=DATA, code_flags=5, extra=None, seed=4):
    rng = random.Random(seed)
    rows = [(1, 256, code_address, code_address, code_bytes, code_memory, code_flags, 4),
            (1, 2048, data_address, data_address, data_bytes, data_memory, 6, 4),
            (4, 192, 0, 0, 36, 36, 4, 4)]
    if extra is not None: rows.append(extra)
    data = bytearray(rng.randbytes(2048 + data_bytes + 32))
    ident = b'\x7fELF' + bytes([1, 1, 1]) + bytes(9)
    data[:52] = struct.pack('<16sHHIIIIIHHHHHH', ident, 2, 243, 1, code_address,
                            52, 0, 0, 52, 32, len(rows), 0, 0, 0)
    for i, row in enumerate(rows): struct.pack_into('<8I', data, 52 + i * 32, *row)
    data[192:228] = struct.pack('<III8s4I', 8, 16, 1, b'PtrocOS\0', 1, 4096, CODE, DATA)
    return data

def expected_memory(data):
    """Reference destination bytes derived only from struct-unpacked file bytes."""
    code, ram = bytearray(b'\xcc' * (CODE_END - CODE)), bytearray(b'\xcc' * (DATA_END - DATA))
    phoff, count = struct.unpack_from('<I', data, 28)[0], struct.unpack_from('<H', data, 44)[0]
    for i in range(count):
        kind, offset, address, _, files, size, _, _ = struct.unpack_from('<8I', data, phoff + i * 32)
        if kind != 1: continue
        target, base = (code, CODE) if CODE <= address < CODE_END else (ram, DATA)
        start = address - base
        target[start:start + size] = data[offset:offset + files] + bytes(size - files)
    return code, ram

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run(['gcc.exe', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-shared',
                    '-o', str(OUT / 'elf_decode.dll'), str(ROOT / 'sw/ptrocos/elf/elf_decode.c')], check=True)
    dll = C.CDLL(str(OUT / 'elf_decode.dll'))
    dll.ptrocos_elf_load.argtypes = [C.POINTER(Source), C.POINTER(Sink), C.POINTER(Image)]
    dll.ptrocos_elf_inspect.argtypes = [C.POINTER(Source), C.POINTER(Image)]
    checks = copied = zeroed = 0

    def run(data, expected=0, fail_read=None, cancel_write=None, fail_write=None):
        nonlocal checks, copied, zeroed
        code, ram = bytearray(b'\xcc' * (CODE_END - CODE)), bytearray(b'\xcc' * (DATA_END - DATA))
        read_calls, writes, violations = [], [], []
        @READ
        def read(_, offset, ptr, count):
            read_calls.append((offset, count))
            if offset + count > len(data): violations.append('source bounds'); return 4
            if fail_read == len(read_calls): return 4
            C.memmove(ptr, bytes(data[offset:offset + count]), count)
            return 0
        @CANCEL
        def cancel(_): return int(cancel_write is not None and len(writes) >= cancel_write)
        @WRITE
        def write(_, address, ptr, count):
            writes.append((address, count))
            if not 0 < count <= 256: violations.append('buffer bound'); return 6
            if fail_write == len(writes): return 6
            if CODE <= address and address + count <= CODE_END: target, base = code, CODE
            elif DATA <= address and address + count <= DATA_END: target, base = ram, DATA
            else: violations.append('destination bounds'); return 6
            target[address - base:address - base + count] = C.string_at(ptr, count)
            return 0
        @PROGRESS
        def progress(_): pass
        source, sink, image = Source(len(data), read, cancel, None), Sink(write, progress, None), Image()
        image.loaded = 0xffffffff
        result = dll.ptrocos_elf_load(C.byref(source), C.byref(sink), C.byref(image))
        assert not violations, violations
        if expected is None: assert result != 0, result
        elif expected != 'either': assert result == expected, (result, expected)
        if result == 0:
            assert image.loaded == image.abi_version == 1
            assert not image.entry & 3 and 1 <= image.count <= 8
            assert any(segment.flags & 1 and segment.address <= image.entry and image.entry + 4 <= segment.address + segment.file_bytes
                       for segment in image.segments[:image.count])
            assert (code, ram) == expected_memory(data), 'Every file/BSS/gap byte'
            copied += image.file_bytes; zeroed += image.memory_bytes - image.file_bytes
        else:
            assert image.loaded == 0
            if result in (1, 2, 3):
                assert not writes and code == b'\xcc' * len(code) and ram == b'\xcc' * len(ram), 'Malformed input modified memory'
        checks += 1
        return result, writes

    valid = fixture()
    run(valid)
    for length in range(52): run(valid[:length], 1)
    fields = [(0, b'NOPE'), (4, bytes([2])), (5, bytes([2])), (6, bytes([0])), (7, bytes([3])),
              (16, struct.pack('<H', 3)), (18, struct.pack('<H', 62)), (20, struct.pack('<I', 0)),
              (28, struct.pack('<I', 0xfffffff0)), (40, struct.pack('<H', 51)),
              (42, struct.pack('<H', 31)), (44, struct.pack('<H', 0)), (44, struct.pack('<H', 9))]
    for offset, replacement in fields:
        bad = valid[:]; bad[offset:offset + len(replacement)] = replacement; run(bad, 1)
    for flags in (1, 2, 4, 6, 8, 16, 32, 0x1000000, 0xffffffff):
        bad = valid[:]; struct.pack_into('<I', bad, 36, flags); run(bad, 3)
    for entry in (0, CODE - 4, CODE + 2, CODE + 600, CODE_END, DATA):
        bad = valid[:]; struct.pack_into('<I', bad, 24, entry); run(bad, 2)
    for field, value in ((1, 0xfffffff0), (4, 951), (7, 3), (7, 4096)):
        bad = valid[:]; struct.pack_into('<I', bad, 52 + field * 4, value); run(bad, 1)
    for address in (0, 0x10000000, 0x40001000, 0x81000000, 0xfffffffc):
        bad = valid[:]; struct.pack_into('<II', bad, 60, address, address); run(bad, 2)
    for kind in (2, 3, 7, 0x70000001):
        bad = valid[:]; struct.pack_into('<I', bad, 52, kind); run(bad, 3)
    for flags in (0, 1, 2, 3, 7, 13):
        bad = valid[:]; struct.pack_into('<I', bad, 76, flags); run(bad, 3)
    bad = valid[:]; struct.pack_into('<I', bad, 64, CODE + 4); run(bad, 2)
    bad = valid[:]; struct.pack_into('<I', bad, 92, DATA_END); struct.pack_into('<I', bad, 96, DATA_END); run(bad, 2)
    for offset in (192, 196):
        bad = valid[:]; struct.pack_into('<I', bad, offset, 0xffffffff); run(bad, 1)
    for offset, value in ((200, 2), (212, 2), (216, 8192), (220, CODE + 4), (224, DATA + 4)):
        bad = valid[:]; struct.pack_into('<I', bad, offset, value); run(bad, 3)
    bad = valid[:]; bad[204] ^= 1; run(bad, 3)
    run(fixture(extra=(4, 192, 0, 0, 36, 36, 4, 4)), 3)
    run(fixture(extra=(1, 2048, DATA + 4, DATA + 4, 4, 4, 6, 4)), 2)
    run(fixture(extra=(0x6474e551, 0, 0, 0, 0, 0, 7, 16)), 3)
    run(fixture(extra=(0x6474e551, 0, 0, 0, 0, 0, 6, 16)))
    run(fixture(code_bytes=4, code_memory=4, code_address=CODE_END - 4,
                data_bytes=16, data_memory=16, data_address=DATA_END - 16))
    run(fixture(data_bytes=0, data_memory=256))
    for size in (1, 2, 3): run(fixture(code_bytes=size), 2)
    for fail in range(1, 13):
        result, _ = run(valid, None, fail_read=fail)
        assert result == 4
    for fail in range(1, 9): run(valid, 6, fail_write=fail)
    for after in range(8): run(valid, 5, cancel_write=after)
    run(valid)  # clean retry after all failed/cancelled attempts
    rng = random.Random(0x454c4631)
    for i in range(256):
        code_bytes, data_bytes = rng.randrange(4, 700), rng.randrange(0, 900)
        run(fixture(code_bytes, code_bytes + rng.randrange(0, 400),
                    data_bytes, data_bytes + rng.randrange(1, 500), seed=i))
    for i in range(512):
        bad = valid[:]
        location = rng.randrange(52)
        bad[location] ^= 1 << rng.randrange(8)
        # Reserved/non-load section fields can legally change. If accepted,
        # compare actual memory to an independently unpacked PT_LOAD image.
        result, _ = run(bad, 'either')
        assert result in range(7)
    print(f'ELF DECODE PASS checks={checks} copied={copied} zeroed={zeroed} prevalidate canaries BSS bounds flags note cancellation retry IO')

if __name__ == '__main__': main()
