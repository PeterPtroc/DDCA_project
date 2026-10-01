`tb_mmio_map.v` locks down the complete v1.0 MMIO map and peripheral readback.
`tb_analyzer_peripherals.v` covers button debounce/event capture, the edge meter,
pattern generator, and UART RX. `tb_logic_capture_v1.v` verifies sample division and
chronological pre-trigger ring-buffer reads.

`tb_soc_mvp.v` retains the original PWM/Capture regression with `mvp.hex`.
`tb_soc_analyzer.v` runs the v1.0 firmware and closes the eight-channel pattern
generator back into Capture; it requires the CPU analysis, edge meter, UART, and final
PASS result to agree.

Run all tests on Windows with `scripts/test_windows.ps1`.

`tb_cpu_trace.v` drives the CPU core directly and writes one CSV row per architectural
retire event. `sw/tools/rv32_ref.py` executes the same firmware in an independent
instruction-level model, and `sw/tools/diff_trace.py` compares PC, instruction, register
writeback, and store side effects. The Windows test script runs this differential check
for `isa_test`, `hazard_test`, and `crc_test`; generated traces are placed in
`build/trace`.
