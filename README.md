# PtrocOS

Nexys A7-100T 上基于自研 RV32IM + Zicsr CPU、FreeRTOS、128 MiB DDR2、VGA、PS/2、microSD 和音频构建的 FPGA 小型计算机。

支持 UART/VGA 双 TTY 与 shell、FAT/exFAT 文件操作、BMP/WAV/PTV 媒体播放、受信任 ELF 应用、DMA 和 CPU 性能计数器。本分支已移除示波器采集、边沿测量、CAP2 导出及 JA 固定波形发生器。构建与使用见 [PtrocOS 开发说明](docs/ptrocos-development.md)。

## 快速启动

需要 64 位 Windows、PowerShell 5.1/7、Python 3（加入 PATH）及 Vivado。固件构建首次自动下载并校验 xPack RISC-V GCC 15.2.0-1，之后复用 `tools/.local/`；固定版本见 [toolchain.json](tools/toolchain.json)。自备工具链可使用 `-ToolchainPrefix` 或 `RISCV_TOOLCHAIN_PREFIX`，详见 [固件说明](sw/freertos/README.md)。

在仓库根目录执行：

```powershell
.\build_freertos.bat
.\open_vivado_gui.bat
```

按提示设置 Vivado 路径，在 GUI 中生成位流，再通过 Hardware Manager 下载。批处理构建可用 `vivado -mode batch -source scripts/build_bitstream.tcl`。固件必须先生成；输出为 `build/hex/freertos.hex` 和 `build/vivado/rv32_realtime_scope.bit`。修改固件或 RTL 后须重新生成并下载位流。

## 构建入口与兼容说明

上面的快速启动保留原文；其中旧命令已转接到完整 PtrocOS ELF 固件，旧输出文件名作为兼容副本保留。`open_vivado_gui.bat` 生成 `build/vivado/ptrocos.xpr`。常规构建、下载与各精简固件入口见 [开发说明](docs/ptrocos-development.md#构建与下载)。

## 板载接口与使用

连接 USB-UART（115200 8N1）、VGA 显示器和 PS/2 键盘；microSD 提供文件与媒体，J8 输出模拟音频。JA/JB 留给扩展，无需跳线。按钮、开关、LED、数码管和 RGB 灯作为通用 MMIO 外设保留。

完整 ELF 固件提供 `help`、`uptime`、`mem`、`tasks`、`ddrtest`、`mount`、`ls`、`cat`、`hexdump`、`bmp`、`wav`、`play`、`run` 等命令；Ctrl+C 取消当前操作。ELF 应用以 M-mode 运行，仅加载可信程序。寄存器与内存布局见 [系统架构](docs/architecture.md)。

## 验证与文档

主工程已包含课设 CPU 仿真：在 **Simulation Sources** 中选择 `sim_pipeline`（数组求和）或 `sim_pipeline_crc`（CRC 校验），点击 **Run Behavioral Simulation**。波形和操作步骤见 [流水线演示](docs/pipeline-demo.md)。

```powershell
.\scripts\test.ps1
.\scripts\test_ptrocos.ps1
python tools/ptrocos_elf_test.py --port COM9
```

第一条验证 CPU、UART 与公共 MMIO；第二条重建全部 PtrocOS 固件并运行本地回归；第三条需要已下载 PtrocOS ELF 位流的板卡。仿真覆盖、复现入口与物理待验项目见 [仿真验证](src/sim/README.md) 和 [开发说明](docs/ptrocos-development.md#验证边界)。

- [系统架构](docs/architecture.md)：CPU、内存、总线、MMIO 和实现门槛。
- [PtrocOS 开发说明](docs/ptrocos-development.md)：构建、命令与各功能文档导航。
- `third_party/freertos/kernel`：FreeRTOS 内核与 MIT 许可证。
- `sw/ptrocos`：系统软件、启动代码、存储、媒体和 ELF 支持。
