# RV32 Real-Time Digital Scope v2.0 Status

Updated: 2026-10-02

## Repository and Baseline

- Branch: `realtime-scope`
- Frozen baseline tag: `v1.0-multichannel-prototype`
- Baseline commit: `62499e2b13c9268ca06f4350e99296ae6497765f`
- Working tree contains the v2.0 implementation and documentation changes.

## Automated Verification

- Windows regression: **PASS** (`WINDOWS TEST PASS`)
- SoC scope integration: **PASS** (`frames=12338`, `frequency=100000`, capture CRC `6858`)
- Synthesis: **PASS**
- Implementation: **PASS**
- Clock: 100 MHz, 10 ns constraint retained
- Routed setup WNS: **+0.024 ns**, 0 failing endpoints
- Routed hold WNS: **+0.035 ns**, 0 failing endpoints
- DRC: 0 errors and 0 critical warnings
- Bitstream: `build/vivado/rv32_realtime_scope.bit`
- Bitstream SHA-256: `933713F7DDE57B287ED80B6541C8FB07FA81726D5A7454FBDB33FC06D77BE39B`
- JTAG programming: **PASS** (Digilent target `210292B7F710A`)

The worst setup path is still inside the CPU, from
`soc/cpu/idex_rs1_reg[0]/C` to the `soc/cpu/pc_reg[*]/CE` control endpoints.
Its 9.701 ns data path contains 2.560 ns logic delay and 7.141 ns route delay
(73.612%). The 10 ns
clock constraint is unchanged and no internal false path is used. The desired
+0.2 ns margin was not reached. The route-dominated CPU control path was
explicitly inspected because WNS is below +0.1 ns; both setup and hold still
meet the plan's hard non-negative requirement.

## Routed Resource Snapshot

- LUTs: 5,194 total (4,554 logic LUTs, 640 LUTRAMs)
- Flip-flops: 3,379
- BRAM36/BRAM18: 0/0 (distributed RAM is used for the current memories)
- DSP blocks: 0

The frozen v1.0 tag was rebuilt with the same Vivado 2024.2 installation for
an equal-basis comparison:

| Metric | v1.0 multichannel | v2.0 scope | Delta |
| --- | ---: | ---: | ---: |
| Total LUTs | 5,939 | 5,194 | -745 (-12.5%) |
| Logic LUTs | 3,891 | 4,554 | +663 (+17.0%) |
| LUTRAMs | 2,048 | 640 | -1,408 (-68.8%) |
| Flip-flops | 2,964 | 3,379 | +415 (+14.0%) |
| BRAM36 / BRAM18 | 0 / 0 | 0 / 0 | unchanged |
| DSP blocks | 0 | 0 | unchanged |
| Setup WNS | +0.061 ns | +0.024 ns | -0.037 ns |
| Hold WNS | +0.035 ns | +0.035 ns | unchanged |

The 8-to-1 channel capture change cuts distributed capture RAM substantially.
The richer live measurement/UI path uses more logic and registers, while total
LUT use remains lower. The final trigger-hardening route uses 2.430%/2.986%
global vertical/horizontal routing. The setup result remains legal but does not
improve on the frozen baseline, so the route-dominated CPU path is recorded
rather than described as a timing improvement.

## Hardware UART Verification

The previous bitstream was programmed before this test. The required physical path
was `JA1 -> Dupont jumper -> JB1`, with SW3 enabled, SW[7:4]=9 (100 kHz),
SW[11:8]=4 (30%), and SW14 enabled. The 2026-10-02 COM9 gate passed:

```text
SCP2 SELFTEST PASS
frequency=100000Hz period=1000 high=301 low=699 duty=30.1%
CAP2 samples=4096 packed=512 trigger=2048 CRC=0x8cd5 ones=2048
PRF2 crc_instructions=538
```

`scripts/test_hardware.ps1 -Port COM9 -RequireSelfTest` generated the physical
CAP2, CSV and VCD artifacts under `build/hardware/`. This proves the final
pre-display-fix bitstream's 100 kHz/30% physical loopback, measurement, packed
transfer, packet CRC and product use of `CRC16.B`.

The display-fix bitstream, SHA-256
`B4F98AF5A9BDFDD1493A19EDB452B5EE73C9BEAF27B41C91297B25001A629CD4`, added
explicit seven-segment `PASS`/`FAIL` self-test pages. On the board the user
observed `PASS` with JA1 -> JB1 connected and `FAIL` with it disconnected;
COM9 independently returned `SCP2 SELFTEST FAIL` for the disconnected case.

The preceding release candidate, SHA-256
`2DBD805C5C896A4338B22813A9EB8C1F0C779928D4A55A252E85CC4A0D5CAE9C`, also
adds the required `HOLD` page. It was programmed successfully; COM9 returned
`SCP2 SELFTEST FAIL` with JA1 -> JB1 disconnected and `SCP2 SELFTEST PASS` after
the jumper was restored. The exact release candidate then passed the complete
hardware gate:

```text
frequency=100000Hz period=1000 high=300 low=700 duty=30%
CAP2 samples=4096 packed=512 trigger=2048 CRC=0x1944 ones=2048
PRF2 crc_instructions=538
```

The final artifacts are under `build/hardware/final/`. The CSV contains 4096
samples plus its header, and an independent CAP2 reparse reproduced a VCD with
the expected 5000 ns step. The user visually confirmed `PASS` and the green
self-test indication on this exact image.

The preceding candidate, SHA-256
`9009120DA08A4ABA16210A6769B0A0CCD0E2EE5CB63E73C756ABA07790C61756`, adds
explicit `Ar` while a SINGLE deep capture is armed and `Err` for the existing
`0xdeadxxxx` fatal-result convention. Full regression, implementation, timing,
DRC and JTAG programming pass. The SoC test asserts both new pages and their RGB
states. After reprogramming this exact image, its 2026-10-02 COM9 gate passed:

```text
SCP2 SELFTEST PASS
frequency=100000Hz period=1000 high=300 low=700 duty=30%
CAP2 samples=4096 packed=512 trigger=2048 CRC=0x1944 ones=2048
PRF2 crc_instructions=1076
```

That image's CAP2, CSV and VCD replaced the files under
`build/hardware/final/`. Ten additional MEA2 samples at 100 kHz/30% were
identical and form the first row of `build/hardware/characterization_final.csv`.
The user also visually confirmed that image showed a stable `PASS`
page and green self-test indication. This closes the current-image self-test UI
check; it does not replace the remaining mode, button, timebase, and no-signal
observations.

The current release candidate, SHA-256
`C1B970187AC0B0AC6DA618D85285CEBB48DC4352717C9B8070C94E32B23B9FD0`, was
rebuilt after replacing the Vivado RTL glob with an explicit production source
set. Legacy multichannel capture, pattern, duplicate PWM, edge-meter and VGA
modules remain available to the regression suite but are absent from the
release project. Implementation still reports setup/hold WNS of
`+0.086 ns`/`+0.051 ns`, and the image was programmed successfully. Its current
100 kHz/20% physical reading and ten-sample characterization are exact at
`100000 Hz`, `1000/200/800 ticks`. At that stage the 100 kHz/30% self-test gate
and visual confirmation had not yet been repeated; the later trigger-hardened
candidate below supersedes this image.

The trigger-hardened release candidate, SHA-256
`933713F7DDE57B287ED80B6541C8FB07FA81726D5A7454FBDB33FC06D77BE39B`,
detects deep-capture trigger edges on every 100 MHz clock while retaining the
shared divider for stored samples. This removes the phase-dependent alias that
could leave `dump` waiting forever at 100 kHz/20%. Full Windows regression and
the rebuilt production implementation pass; setup/hold WNS are
`+0.024 ns`/`+0.035 ns`, and DRC has no error or critical warning. The exact
image was programmed and passed the 100 kHz/30% self-test gate. Three further
consecutive dump/perf cycles completed without reprogramming; each exported a
4096-sample, 512-byte CAP2 packet with CRC `0x146a`. Ten-sample measurements at
100 kHz/30%, every planned 1 kHz duty point, and 10 kHz/20% were exact.
Artifacts and hash-tagged characterization rows are under
`build/hardware/final_933713f7/`.

## Physical Validation Scope Decision

After the current image passed 10 kHz/20%, the user explicitly requested that
the remaining frequency/duty matrix and manual board-UI observations be skipped
and treated as non-blocking for release. `docs/hardware_validation.md` marks each
omitted item as `WAIVED`; it does not relabel unexecuted checks as measured
results. The published input claim is therefore limited to the exact points
actually recorded, despite acceptance of the release.
