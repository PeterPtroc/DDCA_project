# STATUS

## Environment
- Platform: Windows PowerShell
- Python: available
- Vivado/XSim: 2024.2, available
- Board: Digilent Nexys A7-100T detected through JTAG as `xc7a100t`
- XDC: official Digilent Nexys A7-100T pin mapping applied to all 56 top-level
  I/O bits

## Milestones
- [x] M0 directory, Windows test entry point and documentation
- [x] M1 basic CPU combinational modules
- [x] M2 five-stage pipeline, memories and retire interface (basic RTL)
- [x] M3 forwarding, load-use stall and control flush (basic RTL)
- [ ] M4 reference model and differential verification
- [x] M5 MMIO and peripheral RTL (basic RTL)
- [x] M6 minimal SoC integration simulation
- [x] M7 implementation, timing and bitstream
- [ ] M8 physical validation

## Latest checks
- Assembler unit tests: 3/3 PASS.
- MMIO map XSim: PASS for Capture DATA `0x40010000-0x40013fff`, depth 4096,
  PWM readback, UART STATUS, and independent PERF decoding.
- Closed-loop SoC XSim: `MVP PASS`, 9293 cycles, Capture count 32.
- Vivado synthesis for `xc7a100tcsg324-1`: PASS with 0 errors and 0 critical
  warnings; all top-level ports have a package pin and explicit I/O standard.
- Vivado `report_io`: `clk100=E3`, `reset_n=C12`, `uart_tx=D4`,
  `pmod_ja[0]=C17`, and `pmod_jb[0]=D14` verified.
- Vivado implementation: PASS at 100 MHz; setup WNS `+0.108 ns`, hold WNS
  `+0.107 ns`, pulse-width slack `+3.750 ns`, and 0 failing endpoints.
- Final DRC: 0 errors, 0 critical warnings, and 2 warning-level D5/D6 LUT-pair
  placement findings (`PDRC-138`, `PDRC-146`); bitgen completed successfully.
  There are no unclocked or unconstrained internal endpoints.
- Bitstream: `build/vivado/nexys_a7_mvp.bit` (3,825,897 bytes).

## Remaining blockers
- Reference-model and differential CPU tests are not implemented.
- Physical PWM-to-Capture loopback and UART validation are not run yet. The
  JA1-to-JB1 cable is connected and matches `pmod_ja[0]` to `pmod_jb[0]`.

## Next
Program `build/vivado/nexys_a7_mvp.bit`, then perform the physical JA1-to-JB1
loopback and UART checks on the board.
