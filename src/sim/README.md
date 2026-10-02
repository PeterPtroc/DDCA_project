# RTL verification

The course-design verification flow has three testbenches:

- `tb_cpu_trace.v` writes architectural retire traces for `isa_test`, `hazard_test`, and `crc_test`; `rv32_ref.py` and `diff_trace.py` compare PC, instruction, register writeback, and store side effects.
- `tb_scope_core.v` checks the signal generator, edge measurements, live modes/triggers/timebase, 4096-point capture, button events, seven-segment registers, and primary RGB states.
- `tb_soc_realtime_scope.v` runs `scope.S` with the CPU, MMIO, UART, UI, measurement, live scope, and deep capture integrated.

Run all three layers from the repository root:

```powershell
.\scripts\test.ps1
```
