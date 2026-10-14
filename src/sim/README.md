# 仿真验证

想直观看到流水线指令推进、前递、停顿和冲刷，使用 [Vivado 流水线演示](../../docs/pipeline-demo.md)：在空 Vivado 窗口执行 `source scripts/create_pipeline_demo.tcl`。内置短程序，无需固件构建，自动生成按五类功能分组的波形（当前 MEM 实际分为两拍）。

在仓库根目录运行 `.\scripts\test_ptrocos.ps1` 重建全部九种固件并运行 PtrocOS 本地回归，日志保存到 `build/ptrocos-validation/cleanup/`。需要 RISC-V 工具链、Python 和 Vivado XSim；缺少 MIG 引脚模型时自动调用 `scripts/create_ddr2_ip.tcl` 生成。中途修复后可用 `-ResumeFrom <测试脚本名>` 跳过已完成的构建和检查，接着运行该项及后续测试；恢复运行单独报告，不代表之前跳过的项通过。

公共外设与 CPU 快速检查使用 `.\scripts\test.ps1`，不再依赖旧示波器固件。此入口包含 ISA/hazard/CRC 差分、machine-mode、精确中断、UART FIFO，以及 `tb_ptrocos_mmio`：验证撤销页面不会改变 GPIO、RGB、数码管、按键事件或 UART FIFO，验证性能清零和复位。

| 范围 | 入口 |
| --- | --- |
| CPU / 公共 MMIO / UART | `scripts/test.ps1` |
| RV32M / 等待总线 | `scripts/test_rv32m.ps1` / `scripts/test_memory_interface.ps1` |
| DDR2 / MIG 引脚 | `scripts/test_ptrocos_ddr2.ps1` / `scripts/test_ptrocos_mig.ps1` |
| VGA/PS2 / 文本 SoC / TTY | `scripts/test_text_devices.ps1` / `scripts/test_ptrocos_text.ps1` / `scripts/test_ptrocos_shell.ps1` |
| SD SPI / 存储 / 文件 | `scripts/test_sd_spi.ps1` / `scripts/test_ptrocos_storage.ps1` / `scripts/test_ptrocos_files.ps1` |
| 图形 / 媒体 / 视频 | `scripts/test_ptrocos_graphics.ps1` / `scripts/test_ptrocos_media.ps1` / `scripts/test_ptrocos_video.ps1` |
| 无缓存性能 | `scripts/test_ptrocos_perf.ps1` |
| ELF / 可写指令 RAM | `scripts/test_ptrocos_elf.ps1` / `scripts/test_ptrocos_app_memory.ps1` |
| FatFs / 文件原生检查 | `sw/tools/check_fatfs.py` / `sw/tools/check_storage_commands.py` |
| 媒体 / 视频 / ELF 存储原生检查 | `sw/tools/check_media_commands.py` / `sw/tools/check_video_commands.py` / `sw/tools/check_elf_storage.py` |

多数集成脚本默认覆盖两种 PC 实现，参数以脚本 `param` 为准；完整回归也启用 ELF 视频测试。文件 SoC 的 PC_STYLE=0 使用 exFAT、PC_STYLE=1 使用 FAT12；存储 SoC 保留 FAT16/FAT12。历史 Git 冻结断言已移除，测试当前工作树的实际行为。

单项验证前先使用 [构建入口](../../docs/ptrocos-development.md#构建与下载) 生成匹配固件。原生检查只需 Python 与本地 C 编译器。RTL 仿真通过不代表物理板卡验收通过，当前验证记录与物理待验项目见 [开发说明](../../docs/ptrocos-development.md#验证边界)。
