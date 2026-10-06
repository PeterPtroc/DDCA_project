# PtrocOS SD 与 FatFs

本阶段在实验 SoC 中加入 microSD SPI 和 FatFs。原 CPU、原 SoC、原约束、原固件和原构建入口仍以 `80cc06f` 为冻结基线。键盘实物验收按用户要求延期；VGA 显示器未连接。SD 仿真与原生测试的结果不代表实卡验收。

## 接口与固件

SD 引擎使用 100 MHz CPU 时钟，SPI mode 0，MSB 先行。初始化时 SCK 为 400 kHz，进入传输状态后为 12.5 MHz；SCK 是门控数据输出，内部没有新的时钟域。MISO 与卡检测各经两级同步器。最短半周期为 4 个 CPU 周期，正在发送的字节锁存分频值。

引脚依据 [Digilent Master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc)：MISO/DAT0 为 C2，MOSI/CMD 为 C1，SCK 为 B1，CS/DAT3 为 D2，卡检测为 A1，电源控制为 E2。SPI 不使用 DAT1、DAT2。按照[参考手册第 11 节](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf)，`SD_RESET` 必须驱动为低才能给卡座供电。RTL 将卡检测低电平视为插卡；实际检测、电源控制与引脚波形仍需实卡核对。官方[原理图](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7-sch.pdf)保留为板级复核依据。

SD MMIO 基址为 `0x4000d000`，CPU 请求仅路由到新增引擎，不经过原 MMIO 外设。

| 偏移 | 寄存器 | 语义 |
| --- | --- | --- |
| `0x00` | DATA | 低字节写入开始一次交换；读出最后接收字节 |
| `0x04` | STATUS | 位 0..6：busy、done、fault、present、powered、selected、aborted |
| `0x08` | CONTROL | 位 0/1 控制供电与选卡；位 2 取消，位 3 清除完成/错误状态 |
| `0x0c` | DIVIDER | 16 位半周期分频，最小值 4，复位值 125 |
| `0x10` | EXCHANGES | 成功完成的字节交换总数 |

忙时重复写 DATA 会置错且不覆盖正在发送的数据；拔卡或断电会停止交换、拉高 CS，并恢复 SCK 低、MOSI 高。固件对每次交换设 1 ms 超时；协议等待另有时间与轮询次数上限。任务可被定时中断抢占，块间主动让出 CPU。

```powershell
.\scripts\build_ptrocos.ps1 -Firmware storage -ToolchainPrefix <riscv-none-elf前缀>
.\scripts\test_sd_spi.ps1
python sw/tools/check_fatfs.py
.\scripts\test_ptrocos_storage.ps1
.\scripts\test_ptrocos_shell.ps1
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs storage
```

存储应用复用未修改的 FreeRTOS 内核，独立输出 `build/hex/ptrocos_storage.hex` 与 `build/ptrocos_storage_vivado/ptrocos_storage.bit`。两个 TTY 栈各为 1536 个 32 位数据字；堆仍为 24 KiB。普通 shell 构建不启用存储代码。新增条件代码改变了普通 shell 的断言源行号，重编译后的机器码仅有 13 个字节对应这些诊断立即数变化；其完整 SoC 行为回归单独运行。

## SD 协议与文件系统

驱动先断电再上电，在未选卡时输出至少 80 个时钟，依次完成 CMD0、CMD8、CMD55/ACMD41、CMD58、CMD59、CSD/CID 读取。SDSC 使用字节地址并经 CMD16 设置 512 字节块，SDHC 使用块地址。支持 SD v1 SDSC、SD v2 SDSC 和 SDHC/SDXC 的常规 SPI 模式；不支持 MMC、SDUC、UHS 高速模式或 2 TiB 及以上容量。

命令携带 CRC7；卡内 CRC 检查由 CMD59 开启。数据读写使用 SD 的 CRC16-CCITT。文件诊断使用 CPU 原有 CRC 指令，其算法为 CRC16/IBM、初值 `0xffff`；两者用途不同。多块 API 逐块执行 CMD17/CMD24，并报告已成功完成的块数。中途错误使卡状态失效，需要重新挂载。写入被卡接受后发生忙超时，卡上数据可能已改变；错误返回不表示写入没有发生。

FatFs 固定为 R0.16，并严格应用官方 patch 1、patch 2。原始文件与补丁保持下载字节，活动配置位于 `sw/ptrocos/storage/ffconf.h`；版本、许可证及 SHA-256 见 [PROVENANCE.md](../third_party/fatfs/PROVENANCE.md)。

配置支持 FAT12/16/32、MBR 分区与 superfloppy、512 字节扇区、UTF-8 文件名、255 UTF-16 单元长文件名。`FILINFO` 留足最坏 UTF-8 转换空间。启用完整读写 API、4 个对象锁和每卷 FreeRTOS 互斥锁，另以外层互斥锁串行化双 TTY 的挂载、卸载和原始 SD 状态操作。没有 exFAT、GPT、RTC 或格式化命令；无 RTC 时新写文件使用固定 2026-01-01 日期。

当前 shell 的存储命令只读取实卡内容，FatFs 写入接口由原生测试验证，未增加文件写入命令。

| 命令 | 用途 |
| --- | --- |
| `mount` | 初始化卡并立即挂载 FAT；返回类型与容量 |
| `umount` | 卸载 FAT |
| `sdinfo` | 查看卡状态、容量、块读写计数、交换计数与最后错误 |
| `fscheck <path>` | 流式读取整个文件，输出长度与 CRC；Ctrl+C 可取消 |

例如：`mount` 后执行 `fscheck /HELLO.TXT`。TTY 一行最多 63 字节，路径输入也受这个限制；FatFs 本身的长文件名限制更大。CRC、拔卡或取消导致底层失效后，使用 `mount` 重新初始化。

## 验证范围

RTL 单元仿真覆盖 260 次字节交换，包括全部 256 个字节值、mode 0 的边沿和顺序、分频锁存、字节使能、忙时拒绝、取消、拔卡、断电及复位。

原生 SD C 测试用独立 Python SPI 模型验证命令多项式除法和数据 CRC，覆盖 132 项检查：三类卡、块读写、边界、首块/第二块故障、传输中拔卡与取消、恢复、等待超时、计时器回绕及容量溢出。FatFs 原生测试使用独立构造的 FAT12/16/32 和带 MBR 的镜像，共 306 项检查；覆盖 UTF-8、255 单元 LFN、写入/追加、目录扩展、重命名、删除、四线程读取、重新挂载与错误恢复。测试独立解码写回的 FAT 链、LFN、文件字节及两份 FAT，另验证补丁对畸形 FAT-size 字段的拒绝。

完整 SoC 仿真使用真实 GCC 固件、FreeRTOS、CPU、SD MMIO 和引脚级卡模型；MISO 在下降沿后延迟 12 ns。两种 PC 实现分别覆盖 SDHC/FAT16 与 SD v1 SDSC/FAT12。镜像文件跨不连续簇，子目录另含文件；CRC 期望值由主机独立计算。CRC 注错、传输中拔卡、取消与重新挂载在 SDHC 场景中检查。既有 shell 回归继续检查独立双 TTY、PS/2 到 VRAM、DDR DMA、Ctrl+C 和调度器。

实现约束只将异步输入到同步器首级的路径，以及没有同步 I/O 延迟契约的 SPI 输出路径排除；100 MHz 内部状态与同步器级间仍参与时序分析。输出边沿/半周期由独立 SPI 模型验证。实际板上线路延迟、供电、卡检测、卡兼容性、读写及吞吐需要实卡验证，内部 routed 时序不能替代这些项目。

存储固件的 ROM 内容更多，首次布局布线的半周期指令地址路径仅有 +0.062 ns 裕量，被原 +0.100 ns 门禁拒绝。`optimize_ptrocos_rom.tcl` 在布局后对 PC 的 14 个指令地址驱动网做物理寄存器复制，缩短 ROM 地址布线；CPU RTL、100 MHz 频率、ROM 下降沿读取和时序门槛保持不变。常规构建已加入此布局后 hook。`resume_ptrocos_route.tcl storage` 可从该构建的 placed checkpoint 重新布线并执行同一门禁；`storage verify` 从 routed checkpoint 重跑验收并生成位流。恢复时产物固定写入对应 `build/ptrocos_*_vivado/`，不依赖 in-memory project 的工作目录。

具体结果、限制和源文件/产物 SHA-256 保存在 [ptrocos-storage-validation.json](ptrocos-storage-validation.json)。

2026-10-06 结果：SDHC/FAT16 完整 SoC 场景运行 14,529,023 周期，4 次挂载、4 次文件 CRC 通过，并从 CRC 错误、拔卡、Ctrl+C 恢复；SD v1 SDSC/FAT12 场景运行 4,528,490 周期，文件与子目录 CRC 均通过。既有 shell 两种 PC 实现各运行 2,942,284 周期并通过双 TTY、PS/2、DDR DMA 和调度回归。存储任务的最小剩余堆为 7968 字节，UART TTY 最小剩余栈为 997 个数据字。

最终 canonical routed checkpoint 复核：WNS +0.110 ns、WHS +0.038 ns、WPWS +0.206 ns，TNS/THS/TPWS 均为零；无内部未约束端点。DRC 有 15 个 Warning，无 Error 或 Critical Warning；完整 CDC 原有告警保留。已生成存储位流，尚未加载：新的只读 JTAG 探测仍报告目标中没有 FPGA，COM9 FTDI 接口仍存在。实卡初始化、已知文件 CRC、供电/检测极性、卡兼容性与实际吞吐继续保留待验收。

## 实卡验收入口

先通过 JTAG 探测确认目标，再加载 `storage` 易失配置；不写启动 Flash。UART 为 115200 8N1。卡已经有可读 FAT 时，下面只做挂载和状态检查：

```powershell
python tools/ptrocos_storage_test.py --port COM9
```

若卡中有一份已知文件，可对照本地原件验证三次 CRC 和重新挂载后的读取：

```powershell
python tools/ptrocos_storage_test.py --port COM9 --file /SDTEST.BIN --expected <本地原件路径>
```

脚本不复制文件到卡，不格式化或写入卡；使用现有文件即可。原文 UART 和结果 JSON 保存到 `build/ptrocos_storage_hardware/`。没有实卡与可检测的 FPGA 时，这部分保留待验收，继续第 7 阶段的 `ls/cat/hexdump` 软件工作。

## 第 7 阶段的实机补验

2026-10-06 11:42，FPGA 检测恢复并加载文件命令版 `storage` 位流，COM9 UART shell 完整验收及三轮 DDR/DMA CRC 通过。SD 控制器报告 `no-card`，实卡挂载与文件读取继续待验收。键盘实物验收保持延期。详细范围和产物哈希见 [文件命令验收记录](ptrocos-files-validation.json)。
