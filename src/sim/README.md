`tb_mmio_map.v` locks down the corrected Capture address space, depth, UART
STATUS and peripheral readback behavior. `tb_soc_mvp.v` loops the PWM output
back into Capture, runs the real `mvp.hex` firmware, and requires CRC, PWM,
Capture, UART and final status checks to pass before it exits successfully.

Run both tests on Windows with `scripts/test_windows.ps1`.
