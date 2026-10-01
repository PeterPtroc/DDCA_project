# RV32 Digital Analyzer on Nexys A7-100T

This repository contains the basic RTL implementation described by
`nexys_a7_riscv_mvp_codex_plan.md`: a five-stage RV32I pipeline, custom
`CRC16.B`, single-cycle MMIO peripherals, PWM, digital capture, UART TX and
performance counters.

## Current scope

The Windows development flow uses Python and Vivado 2024.2/XSim. The assembler
and reference-model unit tests, CPU differential verification, MMIO address-map
simulation, closed-loop PWM-to-Capture SoC simulation, Vivado synthesis,
implementation, timing, DRC, and bitstream generation have been exercised. The active top-level
ports use the official Digilent Nexys A7-100T package-pin mapping in
`constraints/nexys_a7_100t.xdc`. Physical-board validation passed with the
external JA1-to-JB1 loopback and UART output from the programmed bitstream.

## Layout

- `src/rtl/cpu`: pipeline, decode, ALU, register file, hazards and CRC unit
- `src/rtl/peripheral`: GPIO, UART, timer, PWM, capture and performance counters
- `src/rtl/top`: SoC and Nexys top-level wrappers
- `src/rtl/memory`, `src/rtl/bus`: memories and MMIO interconnect
- `src/sim`: simulation-only sources and testbenches
- `sw/tools/rv32asm.py`: small self-contained assembler
- `sw/tools/rv32_ref.py`: architectural RV32/custom-CRC reference interpreter
- `sw/tools/diff_trace.py`: retire-trace differential checker
- `sw/firmware`: bring-up and directed firmware examples
- `scripts`: Vivado batch project/build entry points
- `build`: generated hex, simulation objects and Vivado output

## Commands

Run the complete Windows verification flow from PowerShell:

```powershell
.\scripts\test_windows.ps1
```

The script assembles all firmware images, runs six Python unit tests, compares
RTL and reference retire traces for ISA, hazard, and CRC firmware, then runs
the MMIO and closed-loop SoC XSim testbenches. To create the Vivado project,
run:

```powershell
vivado -mode batch -source scripts/create_vivado_project.tcl
```

Run a synthesis check without implementation or programming the board:

```powershell
vivado -mode batch -source scripts/check_synthesis.tcl
```

Run implementation, timing and DRC checks, and generate the bitstream:

```powershell
vivado -mode batch -source scripts/build_bitstream.tcl
```

## MMIO

The implemented bases are GPIO `0x40000000`, UART `0x40001000`, timer
`0x40002000`, PWM `0x40003000`, capture control `0x40004000`, performance
counters `0x40006000`, and the 16 KiB capture window
`0x40010000-0x40013fff`. Data RAM is
`0x10000000-0x10000fff`; instruction memory starts at `0x00000000`.
