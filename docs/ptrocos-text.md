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

## 构建与验证

```powershell
.\scripts\build_ptrocos.ps1 -Firmware text -ToolchainPrefix <riscv-none-elf-prefix>
.\scripts\test_text_devices.ps1
.\scripts\test_ptrocos_text.ps1
.\scripts\test_ptrocos_ddr2.ps1
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs text
```

文本工程为 `build/ptrocos_text_vivado/`，DDR2 工程仍为 `build/ptrocos_vivado/`，两套固件和 bitstream 分开输出。重复构建当前源列表创建的工程可使用 `-tclargs text reuse`；更新源列表后使用默认的完整工程创建。Vivado 的 `-tclargs` 必须放在命令末尾。

2026-10-06 自动验证通过：126 万个完整光栅像素，包括所有可打印字符、16 色、消隐、光标、闪烁，以及 byte enable、边界与跨域事务中复位。PS/2 测试发送 328 个包，覆盖全部 256 个字节、错误位、残帧超时、短毛刺、满 FIFO、溢出、同时入队/出队和复位；host 测试调用生产 C 解码器验证 1050 个扫描码字节。

完整 SoC 使用真实 GCC 固件、三种频率的逻辑时钟和 DDR mailbox/AXI 模型。两种 PC 实现各验证 2400 字符写回、字节访问与边界、525704 个寄存器等待周期、9 个键事件写入 VRAM、18 次定时中断，以及显示期间 DDR/DMA 的 48 次 AXI 写和 48 次读。原 DDR2 固件也在新增接口存在时通过两种 PC 实现的回归。

最终板级 100 MHz WNS 为 +0.177 ns，WHS +0.022 ns，WPWS +0.206 ns，无负 slack；DRC 9 条 Warning、零 Error/Critical Warning。CDC 报告仍有原 GPIO 的 16 条 CDC-1 和共同异步复位的 2 条 CDC-10，未做整体豁免。新增 PS/2 与 mailbox toggle 识别为 ASYNC_REG 同步器，视频 mailbox 的 21 位请求和 32 位响应受 10 ns payload 延迟约束。最终输入和结果哈希见 [ptrocos-text-validation.json](ptrocos-text-validation.json)。

## 上板范围与待验收项

固件启动检查字符内存、寄存器及帧计数，并在扫描期间执行 DDR/DMA 小范围复制，完成后进入键盘回显。UART `v` 打印视频、定时中断及 PS/2 状态。

```powershell
vivado -mode batch -source scripts/program_ptrocos.tcl -tclargs <probe打印的target-url> text
python tools/ptrocos_text_test.py --port COM9
# 将来恢复实物输入验收：
python tools/ptrocos_text_test.py --port COM9 --listen-seconds 60
```

已完成板级启动与视频状态检查，证实固件自检结束、帧计数接近 60 Hz、定时中断递增；它不证明 VGA 连接器模拟波形或显示器成像。显示器未连接，实屏验收待补。键盘连接后未观察到字符，供电是否足够尚未确认；用户要求跳过键盘实物验收，留待以后。两项保留待办，不阻塞 TTY/shell 开发。
