# Current Final Status

Updated: 2026-10-02

| Check | Result |
| --- | --- |
| CPU differential: `isa_test` | PASS, 117 retire events |
| CPU differential: `hazard_test` | PASS, 47 retire events |
| CPU differential: `crc_test` | PASS, 26 retire events |
| Scope core | PASS, all 8 fixed JA outputs checked for two periods |
| SoC integration | PASS, JA4 and JA9 loopback cases |
| Synthesis | PASS |
| Implementation | PASS |
| Setup WNS | +0.043 ns |
| Hold WNS | +0.056 ns |
| DRC | PASS, 0 Error / 0 Critical Warning |
| Resources | 5255 LUT, 3385 FF, 640 LUTRAM |
| Fixed JA block | 69 LUT, 104 FF |
| Bitstream | `build/vivado/rv32_realtime_scope.bit` |
| Bitstream SHA-256 | `99E11CDA2545086955B6220EE227FB4A3697A7FE5C5D5537A6808A0F6C3E965E` |
| JTAG programming | PASS, `xc7a100t_0` on Digilent `210292B7F710A` |
| Physical-board loopback | Not run for this image; simulation results only |

The final system is a single-channel real-time digital scope on JB1 plus eight
always-on fixed test outputs on JA. No programmable generator MMIO or switch/UART
configuration path remains.
