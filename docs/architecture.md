# 系统架构

本页描述生产示波器 `nexys_a7_top` / `rv32_core`。PtrocOS 使用独立的 RV32IM CPU、SoC 与顶层，扩展接口见 [开发说明](ptrocos-development.md)。

## 数据通路与 CPU

```text
JB1 → 两级同步器 ┬→ live_scope → 16 位 LED 帧
                ├→ edge_meter_scope → 周期 / 高电平 / 状态
                └→ scope_capture → 4096×1 采集窗口 → MMIO → CPU
JA1/2/3/4/7/8/9/10 ← 独立固定测试计数器
CPU → 八位数码管 / UART
```

三个采样模块共享同一同步输入，独立于 CPU 工作。CPU 计算 `low_ticks` 和 `frequency_hz`，由 FreeRTOS 测量、UI、UART、采集四任务处理配置、显示和传输。

`rv32_core` 为六级流水 RV32I + Zicsr：IF、ID、EX、数据请求、数据响应、WB。支持完整字节/半字/字访存、FENCE/FENCE.I、机器态 CSR、ECALL/EBREAK/MRET、`CRC16.B`、提交跟踪与性能计数器。前递选择在 ID 计算；JAL 在 ID 重定向，JALR/条件分支在 EX 重定向。加载结果在进入 WB 前选择，WB 前递直接使用寄存器输出；对齐检查使用专用有效地址路径。

寄存器、CSR 与异常在 WB 提交，访存副作用在请求级发生。中断遇到已发出的访存时，阻止年轻指令与新请求，先让该访存退休，再进入中断；锁存中断原因，`mepc` 指向最后退休指令的下一 PC，避免返回后重复存储或读后清零。同步异常、MRET、FENCE.I 同样阻止年轻访存越过边界。

CSR：`mstatus/misa/mie/mtvec/mscratch/mepc/mcause/mtval/mip/mhartid/mcycle/minstret`，计数器含高半 CSR。trap 覆盖非法指令、M-mode ECALL、EBREAK、指令/load/store 未对齐及 MSI/MTI。仅支持 M-mode，无 RV32M、S-mode、MMU、PMP 或 PLIC。

取指 BRAM 在下降沿采样；EX 寄存地址后，请求级在上升沿访问同步 BRAM/MMIO，响应级保留元数据，再进入 WB。ROM/RAM 各 64 KiB，ROM 数据只读端口供 `.data` 复制及 `.rodata` 访问；RAM 栈顶 `0x10010000`，16 字节对齐。

## MMIO

| 地址 | 功能 |
| --- | --- |
| `0x00000000..0x0000ffff` | ROM 数据只读端口 |
| `0x10000000..0x1000ffff` | 数据 RAM |
| `0x02000000` / `0x02004000` / `0x0200bff8` | CLINT msip / mtimecmp / mtime |
| `0x40000000` | GPIO / 固件测试结果 |
| `0x40001000` | UART |
| `0x40002000` | 64 位计时器 |
| `0x40004000` | 深度采集控制/状态 |
| `0x40005000` | 实时波形 |
| `0x40006000` | 性能计数器 |
| `0x40007000` | 按钮/开关 |
| `0x40008000` | 八位数码管 |
| `0x40009000` | 边沿测量 |
| `0x40010000..0x40013fff` | 4096 点采样窗口，每字 bit0 为样本 |

`mip.MTIP/MSIP` 反映外设电平，`mie` 与 `mstatus.MIE` 在提交边界决定中断。UART RX FIFO 为 1024 字节；STATUS `0x40001004` 的 bit0..3 为 TX 就绪、RX 非空、粘滞溢出、RX 满。写 bit2=1 清溢出；满且无同时出队时丢弃新字节。

## 采样与测量

实时波形在 AUTO/NORMAL/SINGLE 下把所选边沿对齐 LED7；FREE 每 16 点发布一帧，HOLD 停止发布，AUTO 无触发时强制刷新。时基由 `sample_div` 控制。

深度采集固定 4096 点、触发位置 2048，触发前用环形窗口保留历史，完成后按时间顺序读取。`0x40004010` / `0x40004020` 只读返回深度/预触发点数；`0x4000400c` 配置时基。边沿检测每 10 ns 进行，采样写入仍按分频间隔。

启动时锁存触发边沿与时基，分别从 `0x40004024` / `0x40004028` 读取；随后配置只影响下一次采集。清除/重启优先于同拍采样与触发，防止取消后重新置完成。

边沿测量给出 `period_ticks/high_ticks/edge_age/valid/signal_present`，可选四周期平均，动态无信号超时会清有效状态。固件两次读取周期且一致后更新快照，计算 `low=max(period-high,0)`、`frequency=floor(100000000/period)`；除法由 CPU 执行。

## FreeRTOS 与采集控制

GCC 目标为 `rv32i_zicsr/ilp32`，使用官方 FreeRTOS 11.3.1 RISC-V port，CLINT MTI 驱动 1 kHz tick。启动代码设置 gp/sp、复制 `.data`、清 BSS 并安装 mtvec。测量快照用单元素覆盖队列，采集/导出用任务通知，UART mutex 防止 shell、遥测、错误行与 CAP2 交错。

采集任务每 1 ms 检查完成与通知：新的 SINGLE 重启采集，已有导出请求跟随；重复导出合并。`c` 取消采集及待导出，优先于同时到达的其他请求。期限为 `1000 + ceil(4096 × active_sample_div / 100000)` ms；超时停止采集。CAP2 整帧发送期间保持 UART 锁，发送完再处理通知。

当前裁剪配置启用任务、队列、互斥量、计数信号量、动态分配和通知；软件定时器、静态分配及部分任务 API 关闭，未收录事件组/流缓冲区实现。验收范围限于当前四任务应用。

## CAP2

小端包：26 字节头 + 512 字节位打包样本 + 2 字节 CRC16。

```text
magic[4] version[1] flags[1] count[2] sample_div[4]
trigger_index[2] period[4] high[4] frequency[4]
packed_samples[512] crc16[2]
```

period/high/frequency 来自启动时测量快照，flags/sample_div 来自该次硬件锁存参数，修改开关不会重新标注旧样本。low 由客户端计算。CRC 初值 `0xffff`、多项式 `0xa001`，覆盖头与样本，固件逐字节执行 `CRC16.B`。

## 时序与位流门槛

GUI/批处理共用 `configure_timing.tcl`：ExtraPostPlacementOpt、AggressiveExplore；布线 WNS 在 −0.500～+0.100 ns 且未达标时，仅重试一次物理优化与 NoTimingRelaxation 布线。`finalize_timing.tcl` 保存报告/检查点并要求 **WNS ≥ +0.100 ns、WHS ≥ 0、无 Error/Critical Warning DRC**，生成位流前复查。

CPU 为 100 MHz，下降沿取指半周期路径按 5 ns 分析，无内部假路径或多周期例外。通过的位流发布到 `build/vivado/rv32_realtime_scope.bit`，报告在 `build/vivado/reports/`。2026-10-05 两次干净构建为 WNS +0.315 ns、WHS +0.061 ns，历史报告与输入哈希位于 `build/timing_closure/`。修改 RTL、固件或工具后需重新实现，历史数值不能代替新构建验收。
