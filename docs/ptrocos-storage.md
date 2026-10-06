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

存储应用复用未修改的 FreeRTOS 内核，独立输出 `build/hex/ptrocos_storage.hex` 与 `build/ptrocos_storage_vivado/ptrocos_storage.bit`。两个 TTY 栈各为 1536 个 32 位数据字；堆仍为 24 KiB。普通 shell 构建不启用存储代码。

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

## 验证

复现入口：`scripts/test_ptrocos_storage.ps1`。结果、覆盖范围与产物 SHA 见 [ptrocos-storage-validation.json](ptrocos-storage-validation.json)。统一构建、命令入口和物理待验项见 [开发说明](ptrocos-development.md)。
