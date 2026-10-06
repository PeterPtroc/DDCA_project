# DDR framebuffer 与 VGA graphics

提供 640×480、60 Hz RGB565 扫描，以及 [视频](ptrocos-video.md)使用的 160×120 1bpp 模式。构建与命令入口见 [开发说明](ptrocos-development.md)。

## 内存通路

CPU 与原 DMA 继续使用 32 位 word bridge。新增读主机在 MIG 的 81.25 MHz UI 时钟域读取 128 位 AXI burst，每次最多 16 beat，遇 4 KiB 边界拆分。两路读请求在 burst 边界轮流仲裁，当前 burst 的响应始终送回原主机；CPU 写通路独立。640×480×2×60 对应平均 36,864,000 字节/秒，活动区瞬时需求为 50,400,000 字节/秒。

四个带 frame epoch、行号和错误标记的行槽形成跨时钟行队列。每槽预留 128 个 128 位 word，实际每行使用 80 word；整个队列占两个 RAMB36。像素域通过 held-payload mailbox 请求一行，UI 域写完或排空错误 burst 后发布完成。像素域只有在完成返回、epoch 和行号吻合时读取该槽，直到水平消隐末尾才释放所有权。

每行开始时决定整行是否可用。晚到、错误或缺失的行整行显示黑色，欠载次数增加一次；后续行按自己的标签恢复，避免像素错位或显示旧帧。错误响应和过早/过晚 RLAST 都会使整行失效，读主机持续排空至 RLAST。AXI 永远不返回 RLAST 时仍需联合复位；软件换帧等待会在 1 秒后报告超时，并保留硬件 pending 状态。

NEXT_BASE/NEXT_STRIDE 先暂存，提交时检查整个图像的 64 位地址范围、16 字节对齐和最小 stride，并锁存配置。更新 front buffer 前先排空当前 burst，只在垂直消隐期提交；提交窗口在消隐最后两行关闭，给同步传播留出余量。像素模式在下一帧边界生效。文本与图形使用相同的像素时钟和三拍输出延迟，VGA 同步信号沿用已验证的文本时序。

## 寄存器

基址为 `0x4000e000`，均为 32 位寄存器。

| 偏移 | 名称 | 含义 |
| --- | --- | --- |
| `0x00` | NEXT_BASE | 下一 framebuffer 的完整 CPU 地址，支持字节写入 |
| `0x04` | NEXT_STRIDE | 行间距，单位为字节，支持字节写入 |
| `0x08` | CMD | bit0=提交，bit1=使能值，bit2=清除 sticky 错误；低字节 strobe 有效 |
| `0x0c` | STATUS | bit0=UI 使能，bit1=pending，bit2=配置错误，bit3=读错误，bit4=欠载 sticky |
| `0x10` | ACTIVE_BASE | 已提交的 front buffer 地址 |
| `0x14` | ACTIVE_STRIDE | 已提交的行间距 |
| `0x18` | FRAMES | 最近处理的像素帧 epoch；长时间阻塞后可跳过中间 epoch |
| `0x1c` | SWAPS | 提交次数，包括切回文本模式 |
| `0x20` | UNDERRUNS | 最近帧事件采样的累计缺失行数 |
| `0x24` | READ_BEATS | 已接收的 128 位读 beat，含错误 burst |
| `0x28` | READ_ERRORS | AXI 响应或 RLAST 错误导致的失效行数 |
| `0x2c` | SIZE | `0x01e00280`，高 16 位为 480，低 16 位为 640 |
| `0x30` | FORMAT | `0x565`，原 RGB565 能力标记 |
| `0x34` | NEXT_FORMAT | 0=RGB565，1=160×120 1bpp，完整 32 位写入 |
| `0x38` | ACTIVE_FORMAT | 当前已提交格式 |

启用提交写 CMD=3，关闭提交写 CMD=1，清除 sticky 标记写 CMD=4。清除 sticky 不清除累计计数。忙时再次提交置配置错误，保留原 pending 配置。

## PtrocOS 命令和绘图接口

图形命令：

```text
gfx info
gfx pattern 0
gfx pattern 1
gfx off
gfx clear
```

pattern 0 为八色竖条，pattern 1 为二维 RGB565 渐变。`gfx info` 报告 front buffer、提交次数、帧事件、DDR 读量和错误；`gfx off` 返回文本显示并停止 DDR 扫描；`gfx clear` 清除 sticky 标记。

软件保留 `0x81000000` 和 `0x81100000` 两个 614,400 字节帧缓冲，行间距为 1280 字节。它们与 `ddrtest` 数据区分离。绘图接口 `ptrocos_graphics_begin/row/present/abort` 使用同一个 FreeRTOS mutex 串行化两个 TTY 的完整绘制操作，begin 总是选择当前 front buffer 之外的缓冲。row 写入 320 个打包的 32 位 word，present 在已完成 DDR 写入后执行 fence 并提交换帧。

软件每八行让出 CPU，输入任务可以接收 Ctrl+C。取消尚未提交的绘制只改变 back buffer；已提交的换帧会先等待完成，再释放锁。超时留下的 pending 会在下次 begin 前再次等待，避免误选仍可能成为 front 的缓冲。图形模式期间 VGA TTY 仍能处理命令，其字符单元会在返回文本模式后显示。

复现入口见 [仿真验证](../src/sim/README.md#ptrocos)，已验证范围与物理待验项见 [开发说明](ptrocos-development.md#验证边界)。
