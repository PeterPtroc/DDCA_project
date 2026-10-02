# RTL verification

The course-design verification flow has three testbenches:

- `tb_cpu_trace.v` writes architectural retire traces for `isa_test`, `hazard_test`, and `crc_test`; `rv32_ref.py` and `diff_trace.py` compare PC, instruction, register writeback, and store side effects.
- `tb_scope_core.v` checks two full periods of all eight fixed JA signals, edge measurements, live modes/triggers/timebase, 4096-point capture, button events, seven-segment registers, and primary RGB states.
- `tb_soc_realtime_scope.v` simulates selectable JA4/JA9-to-JB1 jumpers and runs `scope.S` with the CPU, MMIO, UART, UI, measurement, live scope, and deep capture integrated.

Run all three layers from the repository root:

```powershell
.\scripts\test.ps1
```
