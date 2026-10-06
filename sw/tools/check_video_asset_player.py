"""Play a complete local PTV through the C player and independently clocked sinks."""
import argparse
import ctypes as C
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packed', type=Path)
    args = parser.parse_args()
    raw = args.packed.read_bytes()
    magic, size, flags, width, height, fps, frames, rate, frame_bytes, reserved = struct.unpack('<4sHHHHIIIII', raw[:32])
    assert (magic, size, width, height, frame_bytes, reserved) == (b'PTV1', 32, 160, 120, 2400, 0)
    assert 10 <= fps <= 30 and 0 < frames <= fps * 3600
    assert flags == bool(rate) and (not rate or 8000 <= rate <= 16000)
    total_samples = frames * rate // fps
    assert len(raw) == 32 + frames * 2400 + total_samples * 2
    # Only the host oracle allocates a whole-file result array. The actual C
    # player still uses its fixed workspace, eight frame slots and 4096 FIFO.
    limit = max(1, total_samples)
    output = ROOT / 'build/ptrocos_video'
    output.mkdir(parents=True, exist_ok=True)
    library = output / 'video_asset_player.dll'
    subprocess.run(['gcc.exe', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-shared',
        '-DPTROCOS_VIDEO', f'-DVIDEO_NATIVE_MAX_SAMPLES={limit}',
        '-I' + str(ROOT / 'sw/tools/storage_native'), '-I' + str(ROOT / 'sw/ptrocos'),
        *[str(ROOT / path) for path in ('sw/ptrocos/media/video_decode.c', 'sw/ptrocos/media/video_player.c', 'sw/tools/video_player_native.c')],
        '-o', str(library)], check=True)
    lib = C.CDLL(str(library))
    READ = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint)
    CANCEL = C.CFUNCTYPE(C.c_int, C.c_void_p)
    WRITE = C.CFUNCTYPE(None, C.c_void_p, C.c_char_p)
    HOOK = C.CFUNCTYPE(None, C.c_uint, C.c_uint, C.c_void_p)
    class Source(C.Structure):
        _fields_ = [('size', C.c_uint32), ('read', READ), ('cancel', CANCEL), ('context', C.c_void_p)]
    class Work(C.Structure):
        _fields_ = [('input', C.c_uint8 * 2560), ('output', C.c_uint32 * 320)]
    lib.ptrocos_video_play.argtypes = [C.POINTER(Source), C.POINTER(Work), WRITE, C.c_void_p, C.POINTER(C.c_uint32)]
    lib.video_native_hook.argtypes = [HOOK]
    lib.video_native_value.argtypes = [C.c_uint]
    lib.video_native_frames.restype = C.POINTER(C.c_uint32)
    lib.video_native_samples.restype = C.POINTER(C.c_uint16)
    bitmaps, pcm = [], bytearray()
    offset = 32
    for frame in range(frames):
        bitmaps.append(raw[offset:offset + 2400])
        offset += 2400
        amount = (frame + 1) * rate // fps - frame * rate // fps
        pcm.extend(raw[offset:offset + amount * 2])
        offset += amount * 2
    assert offset == len(raw)
    errors, text = [], bytearray()
    checked_bitmaps = checked_samples = reads = 0
    cancel = C.c_uint32(0)
    @READ
    def read(_, offset, destination, count):
        nonlocal reads
        if offset + count > len(raw):
            errors.append('read out of bounds')
            return 2
        C.memmove(destination, raw[offset:offset + count], count)
        reads += 1
        return 0
    @CANCEL
    def cancelled(_):
        return 0
    @WRITE
    def write(_, value):
        text.extend(value)
    @HOOK
    def hook(event, index, pointer):
        nonlocal checked_bitmaps, checked_samples
        try:
            if event in (0, 1):
                assert C.string_at(pointer, 2400) == bitmaps[index], ('bitmap', event, index)
                if event == 0:
                    checked_bitmaps += 1
            elif event == 3:
                assert C.string_at(pointer, 2) == pcm[(index - 1) * 2:index * 2], ('sample', index)
                checked_samples += 1
            elif event == 4:
                errors.append('unexpected audio underrun')
        except Exception as error:
            errors.append(repr(error))
    lib.video_native_reset(0xffffff00)
    lib.video_native_hook(hook)
    source = Source(len(raw), read, cancelled, None)
    result = lib.ptrocos_video_play(C.byref(source), C.byref(Work()), write, None, C.byref(cancel))
    assert result == 0 and not errors, (result, errors[:5], text)
    assert all(lib.video_native_value(index) == 0 for index in (2, 3, 5, 7))
    shown = lib.video_native_value(0)
    indices = [lib.video_native_frames()[i] for i in range(shown)]
    assert indices == list(range(frames)), 'Unexpected dropped, repeated or missing frame'
    assert checked_bitmaps == frames and checked_samples == total_samples
    assert lib.video_native_value(1) == total_samples
    assert C.string_at(lib.video_native_samples(), total_samples * 2) == bytes(pcm)
    match = re.search(rb'PTV played fps=(\d+) frames=(\d+) read=(\d+) displayed=(\d+) dropped=(\d+) elapsed_ms=(\d+) max_late_ms=(\d+) audio_rate=(\d+) playing=(\d+)', text)
    assert match, text
    values = dict(zip(('fps', 'frames', 'read', 'displayed', 'dropped', 'elapsed_ms', 'max_late_ms', 'audio_rate', 'playing'), map(int, match.groups())))
    assert values['elapsed_ms'] >= frames * 1000 // fps and values['audio_rate'] == rate
    values.update(sha256=hashlib.sha256(raw).hexdigest(), pixels=checked_bitmaps * 19200,
        samples=checked_samples, read_calls=reads, native_C_player=True,
        adapted_graphics_and_audio=True, board_playback_verified=False)
    args.packed.with_suffix(args.packed.suffix + '.player-verification.json').write_text(json.dumps(values, indent=2) + '\n', encoding='utf-8')
    print(f'PTV ASSET C PLAYER PASS frames={frames} samples={checked_samples} elapsed_ms={values["elapsed_ms"]} dropped={values["dropped"]}', flush=True)

if __name__ == '__main__':
    main()
