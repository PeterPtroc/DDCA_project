# PtrocOS 双 TTY 与 shell

第 5 阶段在独立 PtrocOS SoC 上运行 FreeRTOS，提供 UART 和 VGA/PS2 两个终端。两个终端各有输入队列、命令行和历史记录；UART 执行等待命令时，VGA 仍可接收键盘并执行命令。原 CPU、RTL、约束、FreeRTOS 内核及原应用均保持不变。

## 调度与内存

固件复用仓库已固定的 [FreeRTOS 11.3.1 内核](../sw/freertos/README.md) 和 RISC-V 移植层，使用独立的 `sw/ptrocos/os/FreeRTOSConfig.h`。CPU 为 100 MHz，CLINT 产生 1 kHz tick，启用抢占和同优先级轮转。任务如下，栈大小单位为 32 位字。

| 任务 | 优先级 | 栈 | 行为 |
| --- | --- | --- | --- |
| heartbeat | 4 | 192 | 每 10 ms 更新心跳和 LED |
| input | 3 | 320 | 每 1 ms 读取 UART 和 PS/2，各轮最多处理 32 字节 |
| uart-tty | 2 | 768 | UART 行编辑、命令执行和串口输出 |
| vga-tty | 2 | 768 | VGA 行编辑、命令执行和字符内存输出 |
| IDLE | 0 | 128 | 空闲任务及调度存活标志 |

只有 UART TTY 写 UART，只有 VGA TTY 写字符内存，避免两个终端混合输出。UART 发送沿用原轮询接口；等待字符发送时仍允许 tick 抢占。每个输入队列可保存 128 个键事件。DDR 自检通过互斥量拥有 DMA 配置和诊断数据区，两个终端不会同时改写这些资源。

代码和只读数据仍从 64 KiB BRAM ROM 执行，数据、任务栈和 24 KiB FreeRTOS heap 位于独立的 64 KiB BRAM RAM。链接脚本为启动及中断栈保留 4 KiB，并检查 ROM/RAM 越界。当前固件 text 为 25,556 字节、data 12 字节、BSS 25,808 字节，HEX 含 6,392 个字。DDR 当前只保存诊断数据。

## 行编辑

提示符为 `ptroc> `，最多输入 63 字节，提示符与输入可放在 VGA 的一行内。支持插入、Backspace、Delete、左右方向键、Home/End，以及各自独立的四条命令历史；向下退出历史浏览时恢复原草稿。Tab 补全唯一匹配的内建命令。Ctrl+A/E/B/F 移动光标，Ctrl+U 清行，Ctrl+K 删除光标后的内容，Ctrl+W 删除前一个词，Ctrl+L 清屏。

UART 识别常用 ANSI CSI/SS3 方向键及 Home/End/Delete 序列，未结束的转义序列等待 100 ms 后复位；CRLF 只执行一次命令。VGA 接收已有 Set-2 解码器输出的字符和键值，在当前行直接重绘并更新硬件光标。命令行超过长度后整行丢弃并提示，不执行截断内容。

输入队列或硬件 FIFO 丢失数据后，终端取消正在执行的命令、丢弃当前行，并忽略剩余输入直到 Enter 或 Ctrl+C，再提示 `input lost; line discarded`。PS/2 传输错误还会清 FIFO 并复位修饰键状态。Ctrl+C 也可取消 `sleep` 或 DDR 自检；DMA 取消等待未完成事务退出后才释放互斥量。

## 命令

参数支持空格分隔、单引号、双引号和反斜杠转义，最多八个参数，含命令名。引号未闭合、末尾转义和参数超限均报语法错误。十进制参数检查溢出。当前不支持管道、重定向、变量展开或运行外部程序。

| 命令 | 行为 |
| --- | --- |
| `help` | 显示命令和编辑按键 |
| `echo ...` | 输出解析后的参数 |
| `clear` | 清当前终端 |
| `uname` | 显示 PtrocOS、ISA、内核版本和板卡 |
| `uptime` | tick、心跳、输入轮询次数及当前终端输入丢失次数 |
| `mem` | heap 当前及历史最小余量，BRAM/DDR 容量 |
| `video` | 帧计数、光标和显示参数 |
| `kbd` | PS/2 状态、收包、错误、超时、溢出、边沿和恢复次数 |
| `tasks` | 五个任务的优先级、状态及栈最小剩余字数 |
| `sleep 0..60000` | 等待指定毫秒数，可用 Ctrl+C 取消 |
| `ddrtest` | 初始化并 DMA 复制 256 个字，逐字及 CRC 校验 |

`ddrtest` 使用 `0x80001000..0x800013ff` 和 `0x80002000..0x800023ff` 两个临时数据区。完成后输出 `DDR DMA PASS words=256 crc=0000f364`。后续存储分配须保留或迁移这些区域。`ls/cat/hexdump` 在 SD 与 FatFs 完成后接入。

## 构建与仿真

```powershell
.\scripts\build_ptrocos.ps1 -Firmware shell -ToolchainPrefix <riscv-none-elf-prefix>
.\scripts\test_ptrocos_shell.ps1
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs shell
```

输出为 `build/ptrocos_shell/`、`build/hex/ptrocos_shell.hex` 和 `build/ptrocos_shell_vivado/ptrocos_shell.bit`。DDR2 和文本诊断固件继续使用各自的构建目录。Vivado 的 `-tclargs` 必须放在命令末尾。

2026-10-06，生产 C 编辑器及参数解析器通过 20,286 个键事件测试，其中 20,000 个随机事件逐步对比独立的字符串参考模型，另检查历史隔离、边界、丢失恢复、ANSI 序列、补全、引号和数值溢出。

完整 SoC 仿真执行真实 GCC 固件、原 FreeRTOS 内核、CPU/DDR/pixel 三域逻辑和 AXI 存储器模型。两种 PC 实现各运行 2,942,284 个 CPU 周期，观察到 64 次 ECALL 调度、28 次定时中断、3 次心跳和 29 次输入轮询，零输入丢失；DDR 自检发生 768 次 AXI 写和 1,536 次读。测试从 UART 引脚解码回显、插入编辑、Ctrl+C 和 CRC 输出，并通过实际 VRAM 内容确认 UART 等待期间 VGA TTY 执行了独立的 `echo VGA-OK`。

共享文本输出库新增重绘函数后，原文本诊断 HEX 逐字节保持一致，SHA-256 为 `c47c6f8a012f9fdaeabfe22eb0107539f59afb634398df11ad2d2b78de6cbe79`。本阶段未改动任何 RTL 或约束，原 CPU 与原 FreeRTOS 文件相对冻结基线的检查继续通过。

独立 shell bitstream 已完成板级布线：100 MHz WNS +0.177 ns、WHS +0.022 ns、WPWS +0.206 ns，全部负裕量总和为零，内部未约束端点为零。DRC 共 9 条 Warning，无 Error/Critical Warning。CDC 原始报告保留 GPIO 的 16 条 CDC-1、共同异步复位的 2 条 CDC-10，以及 MIG 等现有告警；约束及端点门禁沿用文本工程，未增加时钟域豁免。输入、日志和 bitstream 的 SHA-256 见 [ptrocos-shell-validation.json](ptrocos-shell-validation.json)。

## 上板验收

```powershell
vivado -mode batch -source scripts/program_ptrocos.tcl -tclargs <target-url> shell
python tools/ptrocos_shell_test.py --port COM9
```

串口验收脚本发送实际命令和编辑序列，检查引号解析、历史、补全、CRLF、长行丢弃、队列溢出恢复、Ctrl+C、重复 DDR/DMA 校验、heap 与栈余量，以及 tick、心跳、输入轮询和视频帧计数递增。加载只写 FPGA 易失配置。

本次 JTAG 重新启动服务并重连后，USB target 与 COM9 均存在，但未识别到 FPGA，UART 也未响应。shell 位流尚未成功加载，UART 上板验收等待板卡恢复；自动脚本已准备好。前述 shell 验收结果来自完整 SoC 仿真和实际布线。

键盘实物验收按用户要求延期，VGA 实屏验收等待显示器连接。PS/2 到 VGA TTY 的自动验收范围为仿真，不代替真实键盘输入或显示器成像。

## 第 7 阶段的实机补验

2026-10-06 11:42，FPGA 检测恢复并加载文件命令版 `storage` 位流，COM9 UART shell 完整验收及三轮 DDR/DMA CRC 通过。SD 控制器报告 `no-card`，实卡挂载与文件读取继续待验收。键盘实物验收保持延期。详细范围和产物哈希见 [文件命令验收记录](ptrocos-files-validation.json)。
