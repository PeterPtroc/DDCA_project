# Current Final Status

Updated: 2026-10-02

| Check | Result |
| --- | --- |
| CPU differential: `isa_test` | PASS, 117 retire events |
| CPU differential: `hazard_test` | PASS, 47 retire events |
| CPU differential: `crc_test` | PASS, 26 retire events |
| Scope core | PASS |
| SoC integration | PASS |
| Synthesis | PASS |
| Implementation | PASS |
| Setup WNS | +0.029 ns |
| Hold WNS | +0.034 ns |
| DRC | PASS, 0 Error / 0 Critical Warning |
| Resources | 5225 LUT, 3379 FF, 640 LUTRAM |
| Bitstream | `build/vivado/rv32_realtime_scope.bit` |
| Bitstream SHA-256 | `5E3235828A740FAA4BF082FE2DB3292BE562E3EA66ECD97D96CDA8062F92D212` |
| JTAG programming | PASS, Digilent `210292B7F710A` |
| Hardware JA1→JB1 gate | Not signed on this image: board was set to 10 kHz/20% with self-test disabled |

After programming the final image, UART returned a valid 10 kHz measurement (`10000/2001/7999` ticks), but the required 100 kHz/30%/SW14 setup was not physically selected. No hardware PASS is claimed for this rebuilt image.
