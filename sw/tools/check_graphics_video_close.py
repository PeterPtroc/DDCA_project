"""Run the real RV32 graphics cleanup against a delayed MMIO commit model."""
import argparse
import os
from pathlib import Path
import struct
import subprocess

from rv32m_ref import RV32MReference
from rv32_ref import DATA_BASE, u32

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/ptrocos_video/graphics_close'
GFX = 0x4000e000
CALLS = {'xTaskGetTickCount': 0x10000, 'vTaskDelay': 0x10004, 'xSemaphoreGive': 0x10008}
RETURN = 0x1000c
CANVAS = DATA_BASE + 0x100
MUTEX = 0x12345678


class CommitModel(RV32MReference):
    def __init__(self, words, entry, lock_addr, *, enabled=True, pending=False,
                 owned=True, stuck=None, refused=False, tick=0):
        super().__init__(words)
        self.pc = entry
        self.regs[1], self.regs[2], self.regs[10] = RETURN, DATA_BASE + 4096, CANVAS
        self.memory.update({lock_addr: MUTEX, CANVAS: 0x81200000, CANVAS + 4: int(owned)})
        self.enabled, self.pending = enabled, pending
        self.owned = owned
        self.stuck, self.refused, self.tick = stuck, refused, tick
        self.remaining = 3 if pending else 0
        self.disabling = False
        self.commands = self.releases = self.delays = 0

    def load_word(self, addr):
        if addr == GFX + 12:
            return int(self.enabled) | (int(self.pending) << 1)
        return super().load_word(addr)

    def store_word(self, addr, value):
        if addr == GFX + 8:
            assert value == 1 and not self.pending, 'Disable overlapped a pending flip'
            self.commands += 1
            self.pending, self.disabling, self.remaining = True, True, 3
        else:
            super().store_word(addr, value)

    def run_close(self, result, commands, *, restored=True):
        for _ in range(100000):
            if self.pc == RETURN:
                break
            if self.pc == CALLS['xTaskGetTickCount']:
                self.regs[10] = self.tick
            elif self.pc == CALLS['vTaskDelay']:
                assert self.regs[10] == 1
                self.tick = u32(self.tick + 1)
                self.delays += 1
                blocked = self.stuck == ('disable' if self.disabling else 'flip')
                if self.pending and not blocked:
                    self.remaining -= 1
                    if not self.remaining:
                        self.pending = False
                        if self.disabling and not self.refused:
                            self.enabled = False
            elif self.pc == CALLS['xSemaphoreGive']:
                assert self.regs[10] == MUTEX
                assert self.memory[CANVAS + 4] == 0, 'Canvas still owned at unlock'
                if restored:
                    assert not self.enabled and not self.pending, 'Unlocked before text commit'
                self.releases += 1
                self.regs[10] = 1
            else:
                self.step()
                continue
            self.pc = self.regs[1]
        else:
            raise AssertionError('Graphics close did not return')
        assert self.regs[10] == result, (self.regs[10], result)
        assert self.commands == commands, (self.commands, commands)
        assert self.releases == int(self.owned)
        assert self.memory[CANVAS + 4] == 0
        if restored:
            assert not self.enabled and not self.pending


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchain-prefix', default=os.environ.get('RISCV_TOOLCHAIN_PREFIX'), required=not os.environ.get('RISCV_TOOLCHAIN_PREFIX'))
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    elf, binary = OUT / 'close.elf', OUT / 'close.bin'
    prefix = args.toolchain_prefix
    subprocess.run([prefix + '-gcc.exe', '-march=rv32im_zicsr', '-mabi=ilp32',
        '-Os', '-msmall-data-limit=0', '-ffreestanding', '-fno-builtin', '-ffunction-sections', '-fdata-sections',
        '-Wall', '-Wextra', '-Werror', '-DPTROCOS_VIDEO',
        '-I' + str(ROOT / 'sw/tools/storage_native'), '-I' + str(ROOT / 'sw/ptrocos'),
        '-nostdlib', '-Wl,--gc-sections', '-Wl,-Ttext=0', '-Wl,-Tbss=0x10000000',
        '-Wl,--entry=ptrocos_graphics_video_close',
        *[f'-Wl,--defsym={name}={address:#x}' for name, address in CALLS.items()],
        str(ROOT / 'sw/ptrocos/graphics.c'), '-o', str(elf)], check=True)
    subprocess.run([prefix + '-objcopy.exe', '-O', 'binary', str(elf), str(binary)], check=True)
    symbols = {}
    for line in subprocess.check_output([prefix + '-nm.exe', str(elf)], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = int(fields[0], 16)
    raw = binary.read_bytes()
    words = struct.unpack('<' + 'I' * (len(raw) // 4), raw)
    cases = [
        ({}, 0, 1, True),
        ({'enabled': False}, 0, 1, True),
        ({'pending': True}, 0, 1, True),
        ({'pending': True, 'tick': 0xfffffffe}, 0, 1, True),
        ({'owned': False, 'enabled': False}, 0, 0, True),
        ({'pending': True, 'stuck': 'flip', 'tick': 0xfffffffe}, 2, 0, False),
        ({'stuck': 'disable'}, 2, 1, False),
        ({'refused': True}, 3, 1, False),
    ]
    for options, result, commands, restored in cases:
        model = CommitModel(words, symbols['ptrocos_graphics_video_close'], symbols['graphics_lock'], **options)
        model.run_close(result, commands, restored=restored)
    print(f'GRAPHICS VIDEO CLOSE RV32 PASS checks={len(cases)} actual-C pending-flip text-before-unlock timeout tick-wrap invalid idempotent', flush=True)


if __name__ == '__main__':
    main()
