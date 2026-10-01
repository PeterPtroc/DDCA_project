# RV32 Digital Analyzer v1.0 on Nexys A7-100T

This repository implements a stand-alone eight-channel digital analyzer around a
five-stage RV32I CPU. The FPGA can generate test patterns on JA, capture signals on JB
with adjustable rate and pre-trigger history, calculate frequency and duty cycle, and
present results through LEDs, buttons, the eight-digit display, UART, VCD, and a
direct-from-capture VGA waveform viewer.

The original v0.1 hardware baseline is preserved by the annotated tag
`v0.1-hardware-pass`.

## Features

- Five-stage RV32I CPU with forwarding, load-use stall, branch flush, and custom
  `CRC16.B`; retire-trace differential verification is retained.
- 4096 x 8 capture RAM with rising/falling trigger, programmable sample divider,
  configurable pre-trigger ring buffer, and chronological read window.
- 100 MHz edge timestamp meter and iterative frequency divider.
- Eight-channel JA generator: PWM, divided clock, toggle, and constant outputs.
- Debounced buttons, synchronized switches, analyzer-status LEDs, and a hardware-scanned
  eight-digit seven-segment display.
- UART RX/TX command protocol at 115200 8N1, Python CLI, CSV dump, and
  GTKWave-compatible VCD export.
- 640 x 480 VGA timing with eight live capture traces and a trigger marker; capture RAM
  is read directly, without a framebuffer.

## Verification

Run all unit, differential, peripheral, capture, legacy-MVP, and analyzer-SoC
simulations from PowerShell:

```powershell
.\scripts\test_windows.ps1
```

Create the Vivado project once, then run routed timing/DRC and bitstream generation:

```powershell
vivado -mode batch -source scripts/create_vivado_project.tcl
vivado -mode batch -source scripts/build_bitstream.tcl
```

Program an attached Nexys A7-100T and run the automated physical JA1-to-JB1 loopback
test:

```powershell
vivado -mode batch -source scripts/program_analyzer.tcl
.\scripts\test_hardware.ps1 -Port COM9
```

The signed-off output is `build/vivado/nexys_a7_analyzer_v1.bit`. The latest 100 MHz
route has setup WNS `+0.061 ns`, hold WNS `+0.035 ns`, zero failing endpoints, and no
error/critical-warning DRC violations.

## Stand-alone controls

- CENTER: arm a new capture.
- LEFT/RIGHT: select frequency, duty, period, high time, capture count, or CPU stall
  page.
- UP/DOWN: increase/decrease the sampling rate.
- LEDs 0-7: synchronized analyzer input; 8-10: armed/triggered/done; 11: UART activity;
  12: generator enabled; 13: analyzer mode; 14/15: PASS/ERROR.

The default firmware enables a 256-tick, 77-tick-high CH0 test pattern. With a
JA1-to-JB1 cable this is 390625 Hz at 30.078% duty and exercises the complete physical
generator/capture path.

## PC control and VCD export

`tools/analyzer_cli.py` accepts `status`, `arm`, `rate`, `channel`, `edge`, `measure`,
and `dump`. It requires `pyserial`:

```powershell
python -m pip install pyserial
python tools/analyzer_cli.py --port COM9 measure
python tools/analyzer_cli.py --port COM9 dump --output capture.csv --vcd capture.vcd --sample-rate 100000000
```

An existing raw or CSV capture can be converted independently:

```powershell
python tools/capture_dump.py capture.csv capture.vcd --rate 100000000
```

## MMIO map

| Base         | Peripheral        | Notable registers                                                                |
| ------------ | ----------------- | -------------------------------------------------------------------------------- |
| `0x40000000` | GPIO/result       | switches, buttons, LEDs, test result                                             |
| `0x40001000` | UART              | TXDATA `+0x00`, STATUS `+0x04`, RXDATA `+0x08`                                   |
| `0x40002000` | Timer             | 64-bit cycle counter                                                             |
| `0x40003000` | Legacy PWM        | control, period, high time                                                       |
| `0x40004000` | Capture           | control/status/channel/edge/depth/count/trigger index/sample divider/pre-trigger |
| `0x40006000` | Performance       | retire, stall, forwarding, flush, branch, CRC counters                           |
| `0x40007000` | Buttons           | state `+0x00`, clear-on-read event `+0x04`, switches `+0x08`                     |
| `0x40008000` | Seven segment     | data0/data1/decimal points/control                                               |
| `0x40009000` | Edge meter        | status/config, period, high time, frequency                                      |
| `0x4000A000` | Pattern generator | enable, mode, period, high time, data                                            |
| `0x40010000` | Capture window    | 4096 chronological samples through `0x40013FFF`                                  |

Data RAM is `0x10000000-0x10000FFF`; instruction memory starts at `0x00000000` and boots
`build/hex/analyzer.hex`.

## Repository layout

- `src/rtl/cpu`: CPU pipeline, decode, ALU, register file, hazards, CRC unit
- `src/rtl/peripheral`: analyzer, UI, UART, generator, VGA, and legacy peripherals
- `src/rtl/top`: SoC and Nexys A7 top-level wrappers
- `src/sim`: XSim testbenches
- `sw/tools`: assembler, reference model, and retire-trace comparator
- `sw/firmware/analyzer.S`: v1.0 stand-alone firmware
- `tools`: serial CLI and capture/VCD utilities
- `scripts`: regression, implementation, programming, and hardware-test entry points
