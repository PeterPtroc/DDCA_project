# RV32 Digital Analyzer on Nexys A7-100T

This repository contains the basic RTL implementation described by
`nexys_a7_riscv_mvp_codex_plan.md`: a five-stage RV32I pipeline, custom
`CRC16.B`, single-cycle MMIO peripherals, PWM, digital capture, UART TX and
performance counters.

## Current scope

The basic code skeleton is implemented. Simulation, synthesis, bitstream
generation and physical-board validation are intentionally deferred by the
current work request. `constraints/nexys_a7_100t.xdc` is therefore a template;
official Digilent package pins must be filled in before hardware use.

## Layout

- `src/rtl/cpu`: pipeline, decode, ALU, register file, hazards and CRC unit
- `src/rtl/peripheral`: GPIO, UART, timer, PWM, capture and performance counters
- `src/rtl/top`: SoC and Nexys top-level wrappers
- `src/rtl/memory`, `src/rtl/bus`: memories and MMIO interconnect
- `src/sim`: simulation-only sources and testbenches
- `sw/tools/rv32asm.py`: small self-contained assembler
- `sw/firmware`: bring-up and directed firmware examples
- `scripts`: Vivado batch project/build entry points
- `build`: generated hex, simulation objects and Vivado output

## Commands

`make asm` assembles the example firmware. `make lint` performs an Icarus
elaboration check. `make test` currently runs only these build-time checks;
it does not claim simulation or hardware success. `make vivado` creates a
Vivado project under `build/vivado` once Vivado is installed.

## MMIO

The implemented bases are GPIO `0x40000000`, UART `0x40001000`, timer
`0x40002000`, PWM `0x40003000`, capture control `0x40004000`, capture window
`0x40005000`, and performance counters `0x40006000`. Data RAM is
`0x10000000-0x10000fff`; instruction memory starts at `0x00000000`.
