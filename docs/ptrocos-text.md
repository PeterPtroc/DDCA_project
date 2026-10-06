# VGA 文本、PS/2 与 TTY

## 显示与时钟

像素 MMCM 从 100 MHz 生成 25.2 MHz：DIVCLK=5、MULT=31.5、OUTDIV=25，VCO=630 MHz，依据 [AMD 文档](https://docs.amd.com/r/en-US/pg065-clk-wiz/Configuring-Output-Clocks)。

| 时序 | 水平像素 / 垂直行 |
| --- | --- |
| 可见区域 | 640 / 480 |
| 前肩 | 16 / 10 |
| 负极性同步 | 96 / 2 |
| 后肩 | 48 / 33 |
| 总计 | 800 / 525，60 Hz |

80×30 字符，每字符 8×16 像素（字库行重复两次），bit0 为左侧像素，忽略字符码高位，支持 ASCII。公开领域字库见 [来源与哈希](../third_party/font8x8/PROVENANCE.md)。光标为末两行下划线，可常亮或每 32 帧翻转。

字符内存占两个 RAMB36，CPU/像素端各自时钟，无字符双缓冲，同格同时读写可能显示旧值或新值。字符/字库/RGB 三级流水，同步信号延迟一致，消隐输出黑。控制寄存器经 `word_bus_cdc`，请求保持至完成、返回数据保持至下次响应；共同复位、分别同步释放。CDC 仅约束 payload 与首级同步器；BRAM 有效标志单独复位，不对 BRAM 接异步复位。

## 寄存器

| 地址 | 读 / 写语义 |
| --- | --- |
| `0x40010000 + cell*4`，cell=0..2399 | 低字节 ASCII，bits11:8 前景/15:12 背景；支持低两个 byte strobe，上半字读零 |
| 同窗口 cell=2400..4095 | 读零、忽略写 |
| `0x4000b000` | bit0 显示、bit1 光标、bit2 闪烁；复位 1 |
| `0x4000b004` | 12 位光标位置；超过 2399 不显示 |
| `0x4000b008` | 32 位帧计数，回绕 |
| `0x4000b00c` | 几何 `0x001e0050` = 30 行 / 80 列 |
| `0x4000b010` | 光栅位置 bits9:0=x，19:10=y |
| `0x4000b014` | 标称像素时钟 25200000 Hz |
| `0x4000c000` | bits0..6：有数据、溢出、帧错、超时、滤波 clock、data、接收中；bits13:8 FIFO 字节数 |
| `0x4000c004` | 读最老扫描码并弹出；空读零 |
| `0x4000c008` | 正确帧数，包含 FIFO 满时丢弃帧 |
| `0x4000c00c` | 起始/校验/停止位错误数 |
| `0x4000c010` / `0x4000c014` | 超时 / 溢出数 |
| `0x4000c018` | bit0 清 FIFO，bit1 清状态/计数；低字节 strobe 有效 |
| `0x4000c01c` | 滤波 clock 下降沿数，供诊断 |

PS/2 两级同步加连续 8 样本滤波，验证起始位、LSB-first 数据、奇校验及停止位；帧内停顿 2 ms 丢弃残帧。32 字节 FIFO 满时记录丢失，同拍弹出允许入队。板载 PIC 转 USB HID 为 PS/2，FPGA 仅接收、不发键盘命令。协议与引脚依据 [Digilent 手册](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf)及 [Master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc)。

US Set-2 解码支持左右 Shift/Ctrl、Caps Lock、E0、E1 Pause 和 Print Screen 伪 Shift，输出 ASCII 及方向/Home/End/Delete 键值。传输错/溢出后清 FIFO 并重置解码器，避免修饰键粘住。

## TTY 与 shell

UART 与 VGA/PS2 各有独立队列、编辑状态和四条历史。FreeRTOS tick 1 kHz，heartbeat/input/两个 TTY/idle 五任务；堆 24 KiB，存储及上层固件两个 TTY 栈各 1536 个 32 位字。

行长最多 63 字节、8 参数（含命令名），支持单双引号、反斜杠转义、插入、Backspace/Delete、方向/Home/End、Tab 唯一命令补全及 Ctrl+A/E/B/F/U/K/W/L。Ctrl+C 取消；超长行或输入丢失会丢弃整行，防止执行截断命令。无管道、重定向或变量展开。

| 基础命令 | 功能 |
| --- | --- |
| `help` / `echo` / `clear` / `uname` | 帮助 / 参数输出 / 清屏 / 系统信息 |
| `uptime` / `mem` / `tasks` | 调度、输入丢弃、堆与任务栈余量 |
| `video` / `kbd` | 文本控制器 / PS2 状态 |
| `sleep 0..60000` | 可取消的毫秒等待 |
| `ddrtest` | 256 字 DMA 复制与 CRC 检查，见开发说明 |

完整命令、构建和共享内存见 [开发说明](ptrocos-development.md)。共享资源用 mutex，取消等待已发出的总线事务完成后释放。自动 PS2→VGA TTY 验证来自仿真，物理待验范围见 [验证边界](ptrocos-development.md#验证边界)。
