# 仿真验证

## 生产示波器

在仓库根目录运行 `.\scripts\test_freertos.ps1` 重建固件并执行完整回归；已有固件可用 `.\scripts\test.ps1`。缺少 `build/hex/freertos.hex` 会直接失败。

| 测试平台 | 范围 |
| --- | --- |
| `tb_cpu_trace` | isa/hazard/crc 固件与 Python 参考差分，核对 PC、指令、写回及存储副作用 |
| `tb_machine_mode` | 宽度访存、CSR、ECALL/EBREAK/MRET、精确异常、CLINT/MSI/MTI |
| `tb_precise_irq` | 两种 PC、MSI/MTI、电平/脉冲、10 个落点共 80 例；请求与退休只生效一次 |
| `tb_uart_fifo` | 接收顺序、回绕、满队列、溢出、同时入队/出队 |
| `tb_freertos_smoke` | 四任务启动、阻塞切换、定时器 tick、抢占上下文及无意外 trap |
| `tb_freertos_display` | JA4/JA9 跳线模型、测量页、十进制进位/溢出及八位实际段码 |
| `tb_freertos_scope` | UART、RUN/HOLD、SINGLE、CAP2 参数冻结、取消/超时/恢复与 CRC16.B |
| `tb_freertos_uart_burst` | 实际 115200 波特率连续 s/m 命令，核对 5/24 字节响应顺序 |
| `tb_scope_core` | 八路 JA、测量、实时波形、4096 点采集、取消优先级与板载交互 |

范围限于当前裁剪的 FreeRTOS 四任务应用，物理板卡另见 [根 README](../../README.md#验证与文档)。

## PtrocOS

先用 [构建入口](../../docs/ptrocos-development.md#构建与下载) 生成匹配固件，再运行相应脚本。多数脚本默认覆盖两种 PC 实现，具体参数以脚本 `param` 为准；原生工具不需要 Vivado。

| 范围 | 现有入口 |
| --- | --- |
| RV32M / 等待总线 | `scripts/test_rv32m.ps1` / `scripts/test_memory_interface.ps1` |
| DDR2 / MIG 引脚 | `scripts/test_ptrocos_ddr2.ps1` / `scripts/test_ptrocos_mig.ps1` |
| VGA/PS2 / 文本 SoC / TTY | `scripts/test_text_devices.ps1` / `scripts/test_ptrocos_text.ps1` / `scripts/test_ptrocos_shell.ps1` |
| SD SPI / 存储 / 文件 | `scripts/test_sd_spi.ps1` / `scripts/test_ptrocos_storage.ps1` / `scripts/test_ptrocos_files.ps1` |
| 图形 / 媒体 / 视频 | `scripts/test_ptrocos_graphics.ps1` / `scripts/test_ptrocos_media.ps1` / `scripts/test_ptrocos_video.ps1` |
| 无缓存性能 | `scripts/test_ptrocos_perf.ps1` |
| ELF / 可写指令 RAM | `scripts/test_ptrocos_elf.ps1` / `scripts/test_ptrocos_app_memory.ps1` |
| FatFs / 文件原生检查 | `sw/tools/check_fatfs.py` / `sw/tools/check_storage_commands.py` |
| 媒体 / 视频 / ELF 存储原生检查 | `sw/tools/check_media_commands.py` / `sw/tools/check_video_commands.py` / `sw/tools/check_elf_storage.py` |

exFAT 沿用原有检查与 fixture。文件 SoC 的 PC_STYLE=0 使用 exFAT、PC_STYLE=1 使用 FAT12；存储 SoC 保留 FAT16/FAT12。2026-10-07 只重跑了文件与 ELF 的 PC_STYLE=0，不能据此声称此次两种 PC 均通过。已验证范围、未完成回归及物理待验项见 [开发说明](../../docs/ptrocos-development.md#验证边界)。

原文件冻结检查为：

```powershell
git diff --exit-code --diff-filter=MDRT 80cc06f -- src/rtl scripts constraints sw/freertos
```
