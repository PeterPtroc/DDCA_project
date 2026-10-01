`tb_mmio_map.v` locks down the corrected Capture address space, depth, UART
STATUS and peripheral readback behavior. `tb_soc_mvp.v` loops the PWM output
back into Capture, runs the real `mvp.hex` firmware, and requires CRC, PWM,
Capture, UART and final status checks to pass before it exits successfully.

Run both tests on Windows with `scripts/test_windows.ps1`.

`tb_cpu_trace.v` drives the CPU core directly and writes one CSV row per
architectural retire event. `sw/tools/rv32_ref.py` executes the same firmware
in an independent instruction-level model, and `sw/tools/diff_trace.py`
compares PC, instruction, register writeback, and store side effects. The
Windows test script runs this differential check for `isa_test`, `hazard_test`,
and `crc_test`; generated traces are placed in `build/trace`.
