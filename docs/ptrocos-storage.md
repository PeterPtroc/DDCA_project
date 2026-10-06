# SD、FatFs 与文件命令

构建入口见 [开发说明](ptrocos-development.md)，本页适用于 `storage/graphics/media/video/elf` 固件。shell 文件命令只读；FatFs 完整写 API 保留供程序使用。

## SD SPI 接口

SD 引擎使用 CPU 的 100 MHz 时钟，SPI mode 0、MSB 先行；初始化 SCK 400 kHz，传输 12.5 MHz。SCK 为门控输出，无新时钟域；MISO/卡检测使用两级同步器。半周期最小 4 个 CPU 周期，发送字节时锁存分频。

引脚来自 [Digilent Master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc)：MISO/DAT0=C2、MOSI/CMD=C1、SCK=B1、CS/DAT3=D2、卡检测=A1、电源控制=E2。DAT1/2 不使用。[参考手册](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf)第 11 节要求 `SD_RESET=0` 给卡座供电；RTL 以卡检测低电平表示插卡，实际极性与波形仍待实卡核对，[原理图](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7-sch.pdf)可用于复核。

MMIO 基址 `0x4000d000`：

| 偏移 | 寄存器 | 语义 |
| --- | --- | --- |
| `0x00` | DATA | 低字节写入开始交换；读取最后接收字节 |
| `0x04` | STATUS | bits0..6：busy、done、fault、present、powered、selected、aborted |
| `0x08` | CONTROL | bit0/1 供电/选卡，bit2 取消，bit3 清完成/错误状态 |
| `0x0c` | DIVIDER | 16 位半周期分频，最小 4，复位 125 |
| `0x10` | EXCHANGES | 成功完成的字节交换总数 |

忙时重复写 DATA 置错并保留当前数据；拔卡/断电停止交换、CS 拉高、SCK 低、MOSI 高。每次交换限时 1 ms，协议等待也有时间及轮询次数上限；块间让出 CPU。

初始化：断电/上电、未选卡至少 80 个时钟，CMD0、CMD8、CMD55/ACMD41、CMD58、CMD59、CSD/CID。支持 SD v1/v2 SDSC、SDHC/SDXC 常规 SPI；SDSC 用字节地址并以 CMD16 设置 512 字节块，SDHC 用块地址。无 MMC、SDUC、UHS 或 2 TiB 及以上容量支持。

命令 CRC7、数据 CRC16-CCITT，CMD59 开启卡内 CRC 检查。多块 API 逐块 CMD17/CMD24，返回成功块数；错误使卡状态失效。卡已接受写入后的忙超时可能已改变数据，错误不代表未写入。文件诊断 CRC 为 CPU 指令实现的 CRC16/IBM，初值 `0xffff`。

## FatFs 配置

使用 R0.16 加官方 patch 1/2，原始源码/补丁字节、许可和哈希见 [第三方来源](../third_party/fatfs/PROVENANCE.md)，活动配置为 `sw/ptrocos/storage/ffconf.h`。

支持 FAT12/16/32、exFAT、MBR/superfloppy、512 字节扇区、UTF-8 名称及 255 UTF-16 单元 LFN；`FILINFO` 留足最坏 UTF-8 空间。文件大小/seek 为 64 位，块地址为 32 位，容量受 SD 驱动限制。无 GPT、RTC、格式化命令；新写文件日期固定 2026-01-01。

启用 4 个对象锁与每卷 FreeRTOS mutex；外层锁串行化两个 TTY 的挂载、卸载、原始 SD 状态和文件操作。等锁可取消，不改变持锁者的取消源；文件/目录对象在所有出口关闭。

## 命令

先 `mount`。路径从卷根解析，支持 `/SUBDIR/FILE.TXT`、`0:/FILE.TXT`；空格用引号。TTY 行长最多 63 字节且仅接受 ASCII 输入；UART 的 `ls` 可输出 UTF-8 名称，VGA 无 UTF-8 字形。

| 命令 | 行为 |
| --- | --- |
| `mount` / `umount` | 初始化并挂载 / 卸载；类型 1/2/3/4 为 FAT12/16/32/exFAT |
| `sdinfo` | 卡状态、容量、块读写/交换计数与最后错误 |
| `ls [path]` | 默认根目录；指定目录列内容，指定文件列该项。输出 d/f、64 位十进制大小、名称，按目录顺序、不排序 |
| `cat <path>` | 流式输出完整文件，不加换行；UART 原样保留 NUL、CR/LF、ESC、高位字节 |
| `hexdump <path> [offset] [count]` | 无符号十进制偏移/长度，偏移 64 位；默认 0/256，长度最多 4096。每行 16 字节和 ASCII，不压缩重复行；地址为 8 位十六进制，超 32 位时为 16 位 |
| `fscheck <path>` | 整文件 64 位字节数与 CRC16；可取消 |

```text
mount
ls /SUBDIR
cat '/notes/read me.txt'
hexdump /SUBDIR/NESTED.BIN 240 32
umount
```

空文件、hexdump 长度 0/偏移超过 EOF 不输出正文。非法参数先报 usage，不访问卡；读取错误保留 FatFs 数字码及 SD 错误名。目录名称中的控制字符转为 `\xNN`。VGA 的 cat 使用 ASCII 字形及换行/回车/退格/Tab；无换行文件后提示符在当前行重绘，UART 日志保留完整正文。

cat 用 512 字节缓冲，hexdump 用 16 字节读缓冲及 89 字节行缓冲，ls 用单个 FILINFO；每块/目录项后让出 CPU。Ctrl+C 在输出阶段取消会保留挂载；SD 事务取消、拔卡或 CRC 错误导致驱动失效时清挂载，须重新 mount。复现入口见 [仿真验证](../src/sim/README.md#ptrocos)，已验证范围与物理待验项见 [开发说明](ptrocos-development.md#验证边界)。
