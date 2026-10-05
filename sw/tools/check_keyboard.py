"""Exercise the production C decoder through a host DLL and independent key rows."""
import ctypes
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
out = ROOT / "build/ptrocos_text"
out.mkdir(parents=True, exist_ok=True)
subprocess.run(["gcc.exe", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-shared",
                str(ROOT / "sw/ptrocos/keyboard.c"), "-o", str(out / "keyboard.dll")], check=True)

class Keyboard(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint8) for name in
                "extended release pause_bytes left_shift right_shift left_ctrl right_ctrl caps caps_down".split()]

lib = ctypes.CDLL(str(out / "keyboard.dll"))
lib.ptrocos_keyboard_decode.argtypes = [ctypes.POINTER(Keyboard), ctypes.c_uint8]
lib.ptrocos_keyboard_decode.restype = ctypes.c_int
lib.ptrocos_keyboard_reset.argtypes = [ctypes.POINTER(Keyboard)]
state = Keyboard()
cases = 0

def reset():
    lib.ptrocos_keyboard_reset(ctypes.byref(state))

def feed(sequence):
    global cases
    cases += len(sequence)
    return [value for byte in sequence if (value := lib.ptrocos_keyboard_decode(ctypes.byref(state), byte)) >= 0]

rows = [
    ([0x0e,0x16,0x1e,0x26,0x25,0x2e,0x36,0x3d,0x3e,0x46,0x45,0x4e,0x55], "`1234567890-=", "~!@#$%^&*()_+"),
    ([0x15,0x1d,0x24,0x2d,0x2c,0x35,0x3c,0x43,0x44,0x4d,0x54,0x5b,0x5d], "qwertyuiop[]\\", "QWERTYUIOP{}|"),
    ([0x1c,0x1b,0x23,0x2b,0x34,0x33,0x3b,0x42,0x4b,0x4c,0x52], "asdfghjkl;'", 'ASDFGHJKL:"'),
    ([0x1a,0x22,0x21,0x2a,0x32,0x31,0x3a,0x41,0x49,0x4a], "zxcvbnm,./", "ZXCVBNM<>?"),
]
for scans, plain, shifted in rows:
    for shift in (0, 0x12, 0x59):
        for caps in (False, True):
            reset()
            if caps: assert feed([0x58,0xf0,0x58]) == []
            if shift: assert feed([shift]) == []
            expected = shifted if shift else plain
            if caps: expected = ''.join(c.swapcase() if c.isalpha() else c for c in expected)
            assert feed(scans) == list(map(ord, expected)), (shift, caps, expected)
            assert feed([item for scan in scans for item in (0xf0, scan)]) == []
            if shift: assert feed([0xf0,shift]) == []
reset()
assert feed([0x12,0x59,0xf0,0x12,0x1c,0xf0,0x59,0x1c]) == [ord('A'),ord('a')]
reset()
assert feed([0x58,0x58,0x58,0x1c,0xf0,0x58,0x58,0x1c]) == [ord('A'),ord('a')]
for prefix in ([],[0xe0]):
    reset()
    assert feed(prefix+[0x14,0x1c,0x21]+prefix+[0xf0,0x14,0x1c]) == [1,3,ord('a')]
reset()
assert feed([0x0d,0x5a,0x66,0x76,0x29]) == [9,10,8,27,32]
extended = [0x75,0x72,0x6b,0x74,0x6c,0x69,0x71,0x70,0x7d,0x7a]
for index, scan in enumerate(extended):
    assert feed([0xe0,scan,0xe0,0xf0,scan]) == [0x100+index]
assert feed([0xe0,0x5a,0xe0,0x4a]) == [10,ord('/')]
assert feed([0xe0,0x12,0xe0,0x7c,0xe0,0xf0,0x7c,0xe0,0xf0,0x12,0x1c]) == [ord('a')]
assert feed([0xe1,0x14,0x77,0xe1,0xf0,0x14,0xf0,0x77,0x1c]) == [ord('a')]
assert feed([0xaa,0xfa,0xfe,0xff,0,0xe0,0x20,0x1c]) == [ord('a')]
feed([0xe0,0xf0]);reset();assert feed([0x1c]) == [ord('a')]
print(f"KEYBOARD DECODE PASS bytes={cases} all printable US keys modifiers caps repeats extended pause printscreen recovery")

# Reference pixels read the public-domain upstream rows, independent of RTL ROM.
data = (ROOT / "third_party/font8x8/font8x8_basic.h").read_text()
values = [int(value, 16) for row in re.findall(r"\{([^{}]+)\}", data)
          for value in re.findall(r"0x[0-9A-Fa-f]{2}", row)]
assert len(values) == 1024
(out / "font-reference.hex").write_text(''.join(f"{value:02x}\n" for value in values), encoding="ascii")
