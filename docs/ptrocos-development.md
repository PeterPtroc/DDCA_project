# PtrocOS 开发与使用

PtrocOS 是 Nexys A7-100T 的独立 RV32IM + Zicsr 实验系统，使用 FreeRTOS 11.3.1，支持 DDR2/DMA、VGA/PS2、SD、文件与媒体、受信任 ELF 应用。未实现 cache。本分支只保留 PtrocOS 工程；示波器硬件、应用与导出工具已移除。FreeRTOS 内核位于 `third_party/freertos/kernel`，系统启动代码与运行时位于 `sw/ptrocos/os`。

## 构建与下载

需要 Windows PowerShell、Python 3 和 Vivado 2024.2。GCC 使用自动安装的固定工具链；自备工具链可传 `-ToolchainPrefix`。在仓库根目录执行：

```powershell
.\scripts\build_ptrocos.ps1 -Firmware elf
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs elf
vivado -mode batch -source scripts/program_ptrocos.tcl -tclargs <已检测的JTAG-URL> elf
python tools/ptrocos_elf_test.py --port COM9
```

下载脚本连接 `localhost:31234` 的硬件服务器，需要实际 JTAG target URL；`COM9` 替换为实际串口。仅写 FPGA 易失配置。完整固件为 `elf`；也可构建 `ddr2/text/shell/storage/graphics/media/video`，另有仅仿真的 `perf`。默认构建仍为 `ddr2`。

ELF 构建同时生成示例应用；单独构建使用 `scripts/build_ptrocos_apps.ps1`。输出为 `build/hex/ptrocos_elf.hex`、`build/ptrocos_elf/apps/` 和 `build/ptrocos_elf_vivado/ptrocos_elf.bit`。位流必须通过 setup ≥ +0.100 ns、非负 hold/pulse、DRC、CDC 覆盖及音频开漏检查。归档 routed checkpoint 可用 `vivado -mode batch -source scripts/resume_ptrocos_route.tcl -tclargs elf verify` 复核。

GUI、批处理与 checkpoint 恢复共用时序流程：在布局/布线前增加 0.250 ns setup uncertainty 作为优化目标，布线后恢复正常约束并验收。布线后的检查不再执行物理优化，避免 Vivado 2024.2 在优化 PC 寄存器副本时异常退出；setup ≥ +0.100 ns 的验收门槛保持不变。最终验收报告为工程目录内的 `reports/timing_summary.rpt`，Vivado 默认的 route 阶段报告仍使用优化目标。

自动报告改为串行生成，保留功耗、时序和 DRC 等报告。2026-10-09 GUI 实现曾在布线成功后的 `report_power` 启动阶段异常退出，尚未进入自定义验收钩子；单独重放功耗报告及两轮并行报告均通过，因此目前只确认失败阶段，未取得崩溃栈或确认底层根因。

存储及其上层固件采用 `-Os`/LTO，完整 exFAT ELF 固件 ROM 为 60,256 字节，适配 64 KiB。文件命令使用 64 位大小/偏移；BMP/WAV/PTV 与 ELF32 保留 32 位格式范围，拒绝大于 `UINT32_MAX` 的文件。

## 使用与接口

UART 为 115200 8N1，VGA/PS2 与 UART 各有独立 TTY。命令按固件能力提供，完整固件示例：

```text
help
uptime
mem
tasks
ddrtest
mount
ls
cat /HELLO.TXT
hexdump /HELLO.TXT 0 256
bmp /IMAGE.BMP
wav /SOUND.WAV
play /BADAPPLE.PTV
run /HELLO.ELF alpha "two words"
gfx off
umount
```

Ctrl+C 取消当前命令。读卡取消或错误导致挂载失效时重新 `mount`。`audio test`、`video test`、`elf test` 无需 SD 卡。

| 文档 | 内容 |
| --- | --- |
| [文本控制台](ptrocos-text.md) | VGA/PS2 寄存器、TTY 编辑、基础 shell |
| [存储与文件命令](ptrocos-storage.md) | SD、FatFs/exFAT、ls/cat/hexdump、取消规则 |
| [图形](ptrocos-graphics.md) | DDR 扫描、寄存器、帧缓冲所有权 |
| [BMP/WAV](ptrocos-media.md) | 支持格式、音频电路与寄存器 |
| [PTV 视频](ptrocos-video.md) | 转换器、文件格式、帧环与调度 |
| [ELF](ptrocos-elf.md) | 代码/数据窗口、文件校验、M-mode ABI |
| [cache 评估](ptrocos-cache-evaluation.md) | 无缓存性能、地址重放及一致性要求 |
| [仿真验证](../src/sim/README.md) | 测试范围与复现入口 |

## CPU、DDR2 与 DMA

CPU 100 MHz，DDR UI 81.25 MHz，像素 25.2 MHz。RV32M 使用移位加法/恢复除法，普通运算迭代 32 次，覆盖除零与有符号溢出；多周期等待保持精确 trap、中断与单次 MMIO 副作用。

DDR 为 `0x80000000..0x87ffffff`，128 MiB；越界访问 fault。CPU/DMA 通过 32 位 word bridge、128 位 AXI beat 和 held-payload mailbox 访问 DDR。请求等待期间地址/数据保持，完成后只提交一次；CDC 限制 payload 延迟，不对整个时钟域作假路径。

DMA 基址 `0x4000a000`：

| 偏移 | 寄存器 | 语义 |
| --- | --- | --- |
| `0x00` / `0x04` | SOURCE / DESTINATION | DDR 源/目的字节地址，支持 byte strobe |
| `0x08` | WORDS | 32 位字数，支持 byte strobe |
| `0x0c` | COMMAND | bit0 启动，bit1 当前事务完成后取消，bit2 空闲时清状态；低字节 strobe 有效 |
| `0x10` | STATUS | bit0 busy、bit1 done、bit2 error，bits15:8 错误码 |
| `0x14` | COMPLETED | 成功写入的字数 |

启动锁存参数，要求四字节对齐、整个范围在 DDR 内且不重叠；零长度立即完成。错误码 1/2/3/4/5 为未对齐/越界/重叠/总线错误/取消。取消不会撤销已完成写入。`ddrtest` 使用 `0x80001000..0x800013ff` 和 `0x80002000..0x800023ff`，复制 256 字并核对 CRC `0000f364`。

## 验证边界

2026-10-07 本地验证通过：`storage/graphics/media/video/elf` 五个固件构建、现有原生回归及 PC_STYLE=0 的文件/ELF SoC 仿真。日志为 `build/exfat-*.log`，复现入口见 [仿真验证](../src/sim/README.md)。历史完整记录位于 `build/ptrocos-validation/`，与构建产物一起受 Git 忽略，不随克隆分发。

2026-10-09 完整 exFAT ELF 固件已重新综合、实现并生成位流，重新加载 routed checkpoint 复核通过；setup/hold/pulse 最差余量分别为 +0.292/+0.016/+0.206 ns，DRC 无 Error/Critical Warning。构建与复核日志分别为 `build/ptrocos-gui-fix-build.log`、`build/ptrocos-gui-fix-verify.log`。本次位流尚未上板；实卡文件/媒体/ELF、VGA 显示器、J8 模拟音频仍待验，物理键盘按用户要求延期。历史 UART 的 `no-card` 记录只说明当次状态。未取得最终 PASS 的补充视频回归不计通过。

后续自动报告串行化配置已完成固件构建和 Vivado 属性检查（`synth_1`、`impl_1` 的 `GEN_REPORTS_PARALLEL=0`）；该配置的 GUI 实现由用户复跑，尚待验收。

## 分支清理与兼容入口

公共 MMIO 使用 `ptrocos_mmio`，GPIO/UART/timer/perf/按键/数码管地址保持不变。RGB 控制见 [系统架构](architecture.md)。JA/JB 未分配，板卡无需示波器跳线。

根 README 的快速启动段落保留原文。`build_freertos.bat` / `scripts/build_freertos.ps1` 现在构建完整 PtrocOS ELF 固件，并生成 `build/hex/freertos.hex` 兼容副本；`open_vivado_gui.bat` / `scripts/build_bitstream.tcl` 使用相同 PtrocOS ELF 顶层，在 `build/vivado/ptrocos.xpr` 建工程，位流仍发布到 `build/vivado/rv32_realtime_scope.bit`。这些名称仅用于兼容。GUI 启动时核对分支、源码和固件，输入变化时归档旧工程并重建；修改时序脚本后应关闭旧工程，重新运行 `open_vivado_gui.bat`，以更新实现钩子。正式 PtrocOS 入口与默认固件见上文。
