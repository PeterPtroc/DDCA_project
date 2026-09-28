# STATUS

## Environment
- Python: available (`python3`)
- Icarus Verilog: available
- Verilator: available
- Vivado: not detected
- Board/XDC: official package pin mapping not supplied; template only

## Milestones
- [x] M0 directory, Makefile, documentation and tool skeleton
- [x] M1 basic CPU combinational modules
- [x] M2 five-stage pipeline, memories and retire interface (basic RTL)
- [x] M3 forwarding, load-use stall and control flush (basic RTL)
- [ ] M4 reference model and differential verification
- [x] M5 MMIO and peripheral RTL (basic RTL)
- [ ] M6 SoC integration simulation
- [ ] M7 Vivado build
- [ ] M8 physical validation

## Latest checks
- Static Icarus elaboration was run while wiring the MMIO decoder.
- Source tree was reorganized into Vivado-style `src/rtl`, `src/sim`, `sw`,
  `constraints`, `scripts` and `build` directories.
- Full simulation, synthesis and board validation have not been run per request.

## Blockers
- Official Nexys A7-100T master XDC/package pins are required for hardware build.
- Firmware analyzer application and reference/differential test infrastructure remain to be completed.

## Next
Run the planned unit tests, then harden the CPU/MMIO integration and complete
the reference model and full MVP firmware.
