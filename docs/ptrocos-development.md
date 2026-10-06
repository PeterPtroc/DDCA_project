# PtrocOS 开发与使用

开发基线为 `80cc06f144e8c954c662490dbeac25e489bfda8d`。原正确 CPU、生产 SoC/top、原约束、原固件及 FreeRTOS 内核保持冻结；扩展采用独立 CPU/SoC、外设和构建入口。提交到 `PtrocOS`，消息沿用 `[feat]`、`[fix]`、`[improvement]` 加简短中文；未 push。

## 功能与证据

| 顺序 | 内容 | 说明 / 验收 |
| --- | --- | --- |
| 1 | 冻结正确 CPU | 基线回归及原文件 diff 检查 |
| 2 | RV32M | [ISA 验收](rv32m-validation.json)，八个乘除操作、5248 向量、两种 PC 实现各 10001 条退休差分 |
| 3 | DDR2 + DMA | [DDR2 验收](ptrocos-ddr2-validation.json)，握手、AXI、MIG 校准和板卡全容量读写 |
| 4 | VGA text + PS/2 | [接口](ptrocos-text.md) / [验收](ptrocos-text-validation.json) |
| 5 | TTY + shell | [使用](ptrocos-shell.md) / [验收](ptrocos-shell-validation.json) |
| 6 | SD + FatFs | [接口](ptrocos-storage.md) / [验收](ptrocos-storage-validation.json) |
| 7 | ls / cat / hexdump | [命令](ptrocos-files.md) / [验收](ptrocos-files-validation.json) |
| 8 | DDR framebuffer | [图形接口](ptrocos-graphics.md) / [验收](ptrocos-graphics-validation.json) |
| 9 | BMP / WAV | [媒体格式](ptrocos-media.md) / [验收](ptrocos-media-validation.json) |
| 10 | 自定义视频 / Bad Apple | [PTV 格式与转换](ptrocos-video.md) / [验收](ptrocos-video-validation.json) |
| 11 | I/D cache 评估 | [测量与取舍](ptrocos-cache-evaluation.md)，未加入 cache |
| 12 | ELF loader | [ABI 与内存窗口](ptrocos-elf.md) / [验收](ptrocos-elf-validation.json) |

RV32M 使用移位加法/恢复除法，普通运算迭代 32 次，覆盖除零与有符号溢出。多周期等待保留精确 trap、中断和单次 MMIO 提交。DDR CPU 通路使用 32 位 word bridge、128 位 AXI beat 和 held-payload mailbox；DMA 检查对齐、范围和重叠，取消等待已发出的事务完成。图形扫描使用 UI 域 burst 与四个行槽，在垂直消隐原子交换 front。

当前完整固件为 `elf`，保留所有文件和媒体命令。ROM 64,692 字节；CPU 100 MHz、DDR UI 81.25 MHz、像素时钟 25.2 MHz。最终 ELF 位流 setup/hold/pulse 裕量为 +0.268/+0.018/+0.206 ns，内部未约束端点为 0，DRC 无 Error/Critical Warning。UART 的应用诊断、DMA、取消重试、调度及媒体命令已通过。

## 构建与上板

依赖 Vivado 2024.2 与 `riscv-none-elf` GCC；主机视频转换另需 FFmpeg、NumPy。在仓库根目录运行：

```powershell
.\scripts\build_ptrocos.ps1 -Firmware elf -ToolchainPrefix <riscv-none-elf前缀>
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs elf
vivado -mode batch -source scripts/program_ptrocos.tcl -tclargs <已检测的JTAG-URL> elf
python tools/ptrocos_elf_test.py --port COM9
```

可选固件：`ddr2/text/shell/storage/graphics/media/video/elf`；各阶段测试入口保存在 `scripts/test_*.ps1`。应用构建随 ELF 固件生成，也可单独使用 `scripts/build_ptrocos_apps.ps1`。最终 bitstream 为 `build/ptrocos_elf_vivado/ptrocos_elf.bit`，仅写 FPGA 易失配置，不写 Flash。构建必须经过现有时序、DRC、CDC 覆盖及音频开漏检查，不放宽 +0.100 ns setup 门槛。

复核已归档 routed checkpoint 可用：

```powershell
vivado -mode batch -source scripts/resume_ptrocos_route.tcl -tclargs elf verify
```

## 常用命令

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

UART 为 115200 baud。Ctrl+C 取消当前命令；读卡取消或错误使挂载失效时先重新 `mount`。`cat` 原样输出字节，查看二进制用 `hexdump`。`audio test`、`video test` 和 `elf test` 可在没有 SD 卡时运行诊断；ELF 只支持提供的受信任 M-mode ABI，不提供进程隔离。

## 交付与物理待验

原素材在 `build/ptrocos_video/assets/badapple.mp4`，转换片为 `build/ptrocos_video/BADAPPLE.PTV`，FAT16 文件镜像为 `BADAPPLE-SD.img`；均未写物理卡。ELF 示例与 `ELF-SD.img` 在 `build/ptrocos_elf/`。必要的最终产物和验收记录保存于各阶段 snapshot；完整 SHA 清单位于 `build/ptrocos-validation/`，Git 文档保留结果摘要。生成缓存和中间工程可从源码重建。

已验证范围包含独立参考、原生/单元/SoC 模型、实际布线及 UART 状态。真实 SD 当前报告 `no-card`；实卡文件/Bad Apple/ELF 执行、VGA 显示器和 J8 模拟音频仍待验。键盘实物测试按用户要求延期。未结束的补充回归不计为 PASS，具体边界保留在验收 JSON 中。
