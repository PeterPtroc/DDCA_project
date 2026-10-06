# VGA 文本与 PS/2 键盘

第 4 阶段沿用独立的 `ptrocos_soc` 和 `ptrocos_nexys_a7_top`，原 CPU、生产 SoC、原约束及 FreeRTOS 文件保持不变。新增 80×30 字符显示、PS/2 FIFO、US Set-2 扫描码解码和回显诊断固件；TTY 行编辑与 shell 属于后续阶段。

## 显示与时钟

像素 MMCM 从 100 MHz 生成 25.2 MHz：`DIVCLK=5`、`MULT=31.5`、`OUTDIV=25`，VCO 为 630 MHz。CPU 和 DDR 的 200 MHz 参考时钟沿用已有通路。分数倍频依据 [AMD Clocking Wizard 文档](https://docs.amd.com/r/en-US/pg065-clk-wiz/Configuring-Output-Clocks)。

| 项目 | 水平像素 / 垂直行 |
| --- | --- |
| 可见区域 | 640 / 480 |
| 前肩 | 16 / 10 |
| 负极性同步脉冲 | 96 / 2 |
| 后肩 | 48 / 33 |
| 总计 | 800 / 525 |

总计对应 60 Hz。字符宽 8 像素、高 16 行，字库每行重复两次。公开领域字库来源和哈希见 [font8x8/PROVENANCE.md](../third_party/font8x8/PROVENANCE.md)。bit 0 对应左侧像素，字符码高位被忽略；当前支持 ASCII，无中文字体。

字符内存使用两个 RAMB36，CPU 端和像素端各使用自己的时钟。字符读取、字库读取和 RGB 输出为三级流水，同步信号经过相同延迟，消隐区输出黑色。CPU 写入正在扫描的同一字符可能在本帧显示旧值或新值，当前没有字符双缓冲。光标为最后两行的下划线，可常亮或每 32 帧翻转可见状态。

控制寄存器通过 `word_bus_cdc` 传输。CPU 保持请求至完成，返回数据保持至下一次响应；配置在像素域生效。两域共同复位、分别同步释放。约束只限制 mailbox payload 延迟与首级同步器，不切断整个时钟域。BRAM 读输出的有效标志单独复位，BRAM 复位引脚不接异步复位控制。

## MMIO

| 地址 | 读 / 写语义 |
| --- | --- |
| `0x40010000 + cell*4`，cell=0..2399 | 低字节 ASCII，bits 11:8 前景色，15:12 背景色；支持两个低字节写使能，上半字读零 |
| 字符窗口内 cell=2400..4095 | 读零、忽略写入，不映射到有效字符 |
| `0x4000b000` | bit 0 显示开启，bit 1 光标开启，bit 2 光标闪烁；复位值 1 |
| `0x4000b004` | 12 位线性光标位置；大于 2399 时不显示光标 |
| `0x4000b008` | 只读帧计数，32 位回绕 |
| `0x4000b00c` | 只读几何 `0x001e0050` = 30 行 / 80 列 |
| `0x4000b010` | 只读光栅位置，bits 9:0=x，19:10=y |
| `0x4000b014` | 只读标称像素时钟 25200000 Hz |
| `0x4000c000` | bit 0 有数据，1 FIFO 溢出，2 帧错误，3 超时；4 滤波后 clock，5 data，6 帧接收中；bits 13:8 FIFO 字节数 |
| `0x4000c004` | 读取最老扫描码并弹出 FIFO；空 FIFO 读零 |
| `0x4000c008` | 正确帧计数，包含 FIFO 满时丢弃的帧 |
| `0x4000c00c` | 起始位、校验或停止位错误计数 |
| `0x4000c010` | 超时计数 |
| `0x4000c014` | FIFO 溢出计数 |
| `0x4000c018` | 命令 bit 0 清 FIFO，bit 1 清状态与计数；仅低字节写使能有效 |
| `0x4000c01c` | 滤波后 clock 下降沿计数，供实物诊断 |

PS/2 输入使用两级同步器与连续 8 个样本的滤波。接收器验证起始位、LSB-first 数据、奇数校验和停止位，帧内停顿 2 ms 后丢弃残帧。32 字节 FIFO 保持顺序，满时记录丢失；同周期弹出允许同时入队。USB HID 到 PS/2 由板载 PIC 转换，FPGA 当前只接收，不发送键盘命令。协议依据 [Digilent 手册](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf)，引脚依据 [官方 Master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc)。

软件解码处理左右 Shift/Ctrl、Caps Lock 的按下/释放和重复、E0 扩展键、E1 Pause 及 Print Screen 伪 Shift，输出 ASCII 和方向/Home/End/Delete 等键值。传输错误或溢出后清 FIFO 并复位解码器，避免丢失 break 后修饰键保持按下。

## 验证

复现入口：`scripts/test_text_devices.ps1`。结果、覆盖范围与产物 SHA 见 [ptrocos-text-validation.json](ptrocos-text-validation.json)。统一构建、命令入口和物理待验项见 [开发说明](ptrocos-development.md)。
