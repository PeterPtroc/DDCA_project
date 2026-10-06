# DDR framebuffer 与 VGA graphics

第 8 阶段在实验 SoC 中加入 640×480、60 Hz 的 RGB565 DDR 扫描输出。原 CPU、生产顶层、FreeRTOS 内核与原工程入口保持冻结。单元、两种 PC 实现的完整 SoC 仿真、板级时序和串口上板验收均已通过。尚未连接 VGA 显示器，键盘实物验收按用户要求推迟。证据与 SHA-256 见 [ptrocos-graphics-validation.json](ptrocos-graphics-validation.json)。

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
| `0x30` | FORMAT | `0x565`，RGB565 |

启用提交写 CMD=3，关闭提交写 CMD=1，清除 sticky 标记写 CMD=4。清除 sticky 不清除累计计数。忙时再次提交置配置错误，保留原 pending 配置。

## PtrocOS 命令和绘图接口

`graphics` 固件保留 storage 固件的 TTY、shell、SD、FatFs 和文件命令，并增加：

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

## 验证入口

```powershell
.\scripts\build_ptrocos.ps1 -Firmware graphics -ToolchainPrefix <riscv-none-elf前缀>
.\scripts\test_ptrocos_graphics.ps1
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs graphics
vivado -mode batch -source scripts/program_ptrocos.tcl -tclargs <已验证JTAG-URL> graphics
python tools/ptrocos_graphics_test.py --port COM9
```

`-UnitOnly` 运行小尺寸故障/复位用例与完整 640×480 用例；`-SocOnly` 运行真实 RV32IM/FreeRTOS 固件，两种 PC 实现均需通过。像素期望值由独立 Python 生成，并在 VGA 输出引脚逐像素比较；AXI 模型保留完整地址标签，支持 burst 和独立 AW/W/B 等待。测试需要 PASS 标记且不得出现 Fatal。

小尺寸用例检查字节 strobe、stride、对齐、64 位地址溢出、4 KiB 拆分、持续 CPU 读竞争、AXI 错误、错误 RLAST、长时间欠载、忙时提交、整行黑色、错误清除和事务中联合复位。完整尺寸用例比较两个图像的四个完整活动帧，并要求无正常欠载。SoC 用例执行真实绘制、另一个 TTY 的 mutex 等待取消、部分绘制取消、两个缓冲换帧、扫描期间 DDR DMA/CRC 和返回文本模式。

新增六个 mailbox 的数据路径使用 10 ns `max_delay -datapath_only`，只切 first-stage toggle 和异步数据 hold；换帧窗口也使用两级同步器。XDC 只含标准约束命令，端点、物理复制寄存器及实际路径上的 EXCEPTION 属性由普通 Tcl 验收脚本核对。没有整域 false path。

本次 routed setup WNS 为 +0.312 ns、hold WHS 为 +0.052 ns、pulse-width WPWS 为 +0.206 ns，TNS/THS/TPWS 均为零，内部未约束端点为零。DRC 有 57 个 Warning，没有 Error 或 Critical Warning。CDC 原始报告保留 21 个 CDC-1：其中 16 个来自原 GPIO 读取，新增 5 个是 frame mailbox 的单比特模式返回和四个 row mailbox 的单比特错误返回。这些返回数据随 completion toggle 发布，保持至下一次请求，只有两级同步完成后才采样；实际数据路径受 10 ns 上界约束并经过端点验收。报告另有 CDC-15=456 个 held-payload 数据警告，CDC-3=24 个同步器信息，以及原 MIG/联合复位的 CDC-2/8/9/10 标记。没有隐藏这些条目或将 CDC 声称为零。

UART 上板工具核对两个 pattern 的换帧、取消时 front 保持、三次显示期间 DDR DMA/CRC、帧率、约 36.864 MB/s 的扫描带宽、无输入丢失和停止扫描。该工具不把串口计数器验收声明为显示器目视验收；实物 VGA 显示仍待以后连接显示器检查。

2026-10-06 上板记录：`xc7a100t_0` 已加载通过门槛的 graphics 位流，COM9 验收 11 项检查全部通过。采样帧率为 59.27 Hz、DDR 扫描读量为 36.37 MB/s，Ctrl+C 返回延迟约 16 ms；两次完整画面换帧与一次取消均按预期保持 front buffer。显示期间三次 DDR DMA 的独立 CRC 为 `0xf364`，全部通过，扫描累计 4,569,600 个 128 位 beat，没有欠载、读错误或输入丢失。返回文本模式后读量停止增加。另运行完整 UART shell 验收，33 项检查通过，包括故意制造一次输入队列溢出并恢复。

小尺寸测试逐像素比对 5375 个活动像素，独立检测 152 条全黑失效行，并完成事务中复位和恢复；完整尺寸测试比对 1,228,800 个像素，同时进行 1,239,864 次 CPU 读。真实固件的两种 PC 实现各比对 3,993,600 个像素，运行 48,332,678 个 CPU 周期，接收 482 次定时中断，无正常扫描错误。固件 ROM 镜像为 60,052 字节，BSS 为 27,856 字节。
