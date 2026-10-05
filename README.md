# RV32 实时数字示波分析仪

## 快速启动

安装Python 3并确保python.exe已加入 PATH。

### 1. 编译固件

双击根目录的 `build_freertos.bat`，或在终端运行：

```powershell
.\build_freertos.bat
```


### 2. 打开vivado项目

```powershell
.\open_vivado_gui.bat
```
（或者双击打开）
需要按提示填入vivado安装路径

请先编译固件；固件缺失时会直接报错。

或者使用无头
```powershell
vivado -mode batch -source scripts/build_bitstream.tcl
```

### 3. 下载到板卡


生成bitstream后，使用 Vivado GUI 的 Hardware Manager 下载到板卡即可。


## 项目概述

本项目在 Nexys A7-100T 上实现一套单通道实时数字示波分析仪，并提供 8 路固定板载测试信号。系统只接收 3.3 V 数字信号：唯一的测量输入 JB1 经同步后，同时送入实时波形、边沿测量和 4096 点深度采集模块。RV32 CPU 负责示波器配置、板载交互、UART 通信和采集管理。

```text
JB1 -> 两级触发器同步器 -> 实时波形 ------> LED[15:0]
                         +-> 边沿测量 -----> RV32 CPU -> 八位数码管 / UART
                         +-> 4096×1 深度采集

JA1/2/3/4/7/8/9/10 <- 8 路固定测试信号（持续输出）
```

## 主要功能

- 自研六级流水 `RV32I + Zicsr` CPU，支持 M-mode、精确异常/中断、数据前递、加载-使用冒险停顿、控制冒险冲刷、自定义 `CRC16.B`、指令提交跟踪和性能计数器
- 完整的 `LB/LBU/LH/LHU/LW`、`SB/SH/SW`、`FENCE/FENCE.I`，并对未对齐指令、加载和存储产生规范 trap
- 标准机器态 CSR、`ECALL/EBREAK/MRET`，以及 `mtime/mtimecmp/msip` CLINT（地址与常见 RISC-V 平台一致）
- 64 KiB 指令 BRAM和 64 KiB 数据 BRAM；数据侧只读 ROM 端口用于 C 运行时复制 `.data` 和读取 `.rodata`
- GCC `rv32i_zicsr/ilp32` C 运行时和官方 FreeRTOS Kernel V11.3.1 RISC-V port，启用 1 kHz 抢占式调度
- FreeRTOS 中的测量、UI、UART 和采集四任务应用，使用队列和任务通知传递测量/采集事件
- UART 接收端使用 1024 字节 FIFO；深度采集冻结时基和触发边沿，支持请求超时与取消
- 单通道 16 点 LED 实时波形，支持 `AUTO`、`NORMAL`、`SINGLE`、`FREE` 和 `RUN/HOLD`
- 上升沿/下降沿触发与 16 档时基
- 边沿测量硬件计算 `period_ticks` 和 `high_ticks`，并检测无信号超时；CPU 计算 `frequency_hz` 和 `low_ticks`，供占空比显示、UART 响应和 CAP2 数据包使用
- 4096×1 深度采集，触发位置固定为第 2048 点
- JA 的 8 路数字输出持续产生固定频率、固定占空比的测试波形
- 八位数码管、RGB 状态灯、按钮、开关和 115200 8N1 UART
- 支持导出 CAP2、CSV 和 VCD；CAP2 校验使用 CPU 自定义指令计算 CRC16

## 连接与运行

演示时先断电，用一根杜邦线将下表任一路 JA 输出连接到唯一测量输入 `JB1`，再上电并根据固定表检查测量结果。运行硬件验证脚本时使用 `JA9 -> JB1`。

| 固定输出 | 频率 | 占空比 | 周期计数 | 高电平计数 |
| --- | ---: | ---: | ---: | ---: |
| JA1 | 1 kHz | 20% | 100000 | 20000 |
| JA2 | 2 kHz | 30% | 50000 | 15000 |
| JA3 | 5 kHz | 40% | 20000 | 8000 |
| JA4 | 标称 14,242 Hz | 标称 50% | 7021 | 3511 |
| JA7 | 20 kHz | 60% | 5000 | 3000 |
| JA8 | 50 kHz | 70% | 2000 | 1400 |
| JA9 | 100 kHz | 80% | 1000 | 800 |
| JA10 | 200 kHz | 90% | 500 | 450 |

JA 是 12 针 Pmod 接口：JA1–JA4、JA7–JA10 是上述 8 路数字输出；JA5/JA11 是 GND，JA6/JA12 是 3.3 V 电源，不能作为额外信号输出。JA4 受 100 MHz 整数时钟计数限制，实际输出为 14,242.985 Hz、50.007%。

项目创建、编译和 JTAG 下载按前文 [快速启动](#快速启动) 执行。完成接线与下载后，可运行串口验证；将 `COM9` 替换为设备管理器中板卡对应的串口号：

```powershell
.\scripts\test_hardware.ps1 -Port COM9
.\scripts\test_hardware_soak.ps1 -Port COM9 -DurationMinutes 10
```

固件编译需要 64 位 Windows、PowerShell 5.1 或 7，以及已加入 PATH 的 Python 3。直接运行 `.\scripts\build_freertos.ps1` 即可：首次调用会自动从 GitHub 下载固定的 xPack RISC-V GCC **15.2.0-1** ZIP，校验 SHA-256 后解压到 `tools/.local/`；以后复用本地工具链，可离线编译。版本、下载地址与校验值记录在 [tools/toolchain.json](tools/toolchain.json)，工具链和下载缓存均由 Git 忽略。也可提前运行 `.\scripts\setup_toolchain.ps1` 安装工具链。

生成的位流位于 `build/vivado/rv32_realtime_scope.bit`，默认固件为 `build/hex/freertos.hex`。已有工具链可通过 `-ToolchainPrefix` 指定，或设置 `RISCV_TOOLCHAIN_PREFIX` 环境变量；显式参数优先，两者均会跳过自动安装。旧的完整单循环示波器固件仍保留为 `scope.S`，用于兼容回归。

如需同时检查 FreeRTOS 固件的 CAP2/CSV/VCD 导出和 CRC 指令计数，可运行：

```powershell
.\scripts\test_hardware.ps1 -Port COM9 -OptionalDump
```

硬件测试默认假设 JA9 跳接 JB1；若使用其他板载测试输出，可指定 `-ExpectedOutput`，例如当前接线为 JA1 时运行 `-ExpectedOutput JA1`。
`test_hardware_soak.ps1` 会周期检查 UART、测量结果及 `cycle/instret` 计数器，并在 `build/hardware` 保存带时间戳的持续运行日志。

> JB1 只允许接入 3.3 V LVCMOS 兼容数字信号。本项目没有模拟前端、衰减网络或过压保护，不能连接 5 V、RS-232、电源轨或未知电平。

## 板载控制

| 输入 | 作用 |
| --- | --- |
| SW0 | 上升沿 / 下降沿 |
| SW[2:1] | AUTO / NORMAL / SINGLE / FREE |
| SW12 | 四周期测量平均 |
| SW13 | MEA2 周期遥测 |
| SW15 | CPU 性能计数器页 |
| CENTER | 切换 RUN/HOLD；在 SINGLE 模式下启动采集 |
| LEFT / RIGHT | 切换显示页 |
| UP / DOWN | 更快 / 更慢时基 |

SW3–SW11 和 SW14 未分配功能。RGB0 显示 RUN、HOLD、SINGLE 等待或错误状态；RGB1 显示有效信号、等待触发或无信号状态。LED0 对应实时帧中最早的采样点，LED15 对应最新的采样点。

## UART 与离线导出

安装 `pyserial` 后，可以查询状态和测量值、控制 RUN/HOLD/SINGLE，或导出深度采集结果：

```powershell
python -m pip install pyserial
python tools/analyzer_cli.py --port COM9 status
python tools/analyzer_cli.py --port COM9 measure
python tools/analyzer_cli.py --port COM9 dump --output capture.csv --vcd capture.vcd --packet capture.cap2
python tools/analyzer_cli.py --port COM9 cancel
python tools/analyzer_cli.py --port COM9 perf
```

FreeRTOS 固件的采集等待期限为 1 秒触发等待余量加上 `4096 × sample_div / 100 MHz` 的采样时间（向上取整到毫秒）。超时后停止该次深度采集并返回 `ERR2 TIMEOUT`；`cancel` 发送 `c`，清除采集和待导出请求，返回 `ERR2 CANCELLED`。等待期间仍可接收新的 SINGLE 请求来重新采集。客户端默认串口超时为 10 秒；导出读取超时时会自动发送 `c`。CAP2 帧开始发送后会完成整帧传输，再处理取消请求。

已有的 CAP2 数据包也可以单独转换：

```powershell
python tools/capture_dump.py capture.cap2 capture.vcd --csv capture.csv
```

## 验证

`scripts/test.ps1` 要求存在 `build/hex/freertos.hex`，缺失时直接失败，不再跳过 FreeRTOS 后报告整体 PASS。它运行以下验证：

1. `tb_cpu_trace` 与 Python 参考模型：`isa_test`、`hazard_test`、`crc_test`
2. `tb_machine_mode`：CSR、ECALL/EBREAK/MRET、精确 trap、宽度访存、未对齐异常、MSI/MTI 和 CLINT
3. `tb_precise_irq`：两种 PC 实现、MSI/MTI、电平/脉冲和 10 个中断落点，共 80 例，检查连续写与读后清零操作只生效和退休一次
4. `tb_uart_fifo`：连续接收、顺序、指针回绕、满队列、溢出和同时入队/出队
5. `tb_freertos_smoke`：官方 RISC-V port、四任务启动、阻塞切换、机器定时器 tick 和抢占式上下文保存
6. `tb_freertos_scope`：RTOS UART shell、RUN/HOLD、测量/性能响应、SINGLE、CAP2 参数冻结、取消、超时和恢复
7. `tb_freertos_uart_burst`：按实际 115200 波特率连续发送 `s`、`m`，检查两条响应的顺序和完整性
8. `tb_scope_core`：8 路固定测试波形、边沿测量、实时波形、采集中修改配置、深度采集和基础交互
9. `tb_soc_realtime_scope`：兼容验证 JA4/JA9 模拟跳线、CPU、`scope.S`、MMIO 和各外设

`scripts/test_freertos.ps1` 会先用 GCC 重建 FreeRTOS，再执行全部 RTL/SoC 回归。

当前 FreeRTOS 为裁剪配置：启用任务、队列、互斥量、计数信号量、动态分配和任务通知；未启用软件定时器、静态分配和部分任务管理 API，也未收录事件组与流缓冲区的实现。这里的测试范围是当前四任务示波器应用，不能据此认定完整 FreeRTOS 功能或板上可靠性已经验证。

模块关系和实现细节见 [系统架构](docs/architecture.md)，仿真分层与测试范围见 [仿真验证](src/sim/README.md)。
