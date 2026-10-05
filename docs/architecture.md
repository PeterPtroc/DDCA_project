# 系统架构

## 数据通路

```text
JB1 异步输入
        |
   两级触发器同步器
        |
        +---- 实时波形 ------ 16 位采样帧 ------ LED[15:0]
        +---- 边沿测量 ------ 周期/高电平/状态
        +---- 深度采集 ------ 4096×1 采样窗口
                                           |
                                           v
六级流水 RV32I/Zicsr CPU <---- MMIO --------+---- 八位数码管
        |                                  +---- UART
        +---- M-mode / precise trap / CLINT
        +---- 数据前递 / 加载-使用停顿 / 分支冲刷
        +---- CRC16.B / 指令提交跟踪 / 性能计数器

8 路固定测试计数器 ----------------------- JA1/2/3/4/7/8/9/10
```

输入只经过一组 `input_sync`，三个模块共享同一个同步结果。实时数据通路不等待 CPU：`live_scope` 发布 LED 帧，`edge_meter_scope` 完成边沿计时并保留原始的 `period_ticks` 和 `high_ticks`，`scope_capture` 管理环形采样窗口。CPU 默认运行 FreeRTOS 应用，由测量、UI、UART 和采集四个任务处理示波器配置、按钮事件、数码管内容、UART 通信和深度采集传输；旧 `scope.S` 仅用于兼容回归。CPU 根据一致性快照计算 `low_ticks` 和 `frequency_hz`，再将队列中的快照用于显示和传输。JA 固定测试输出独立于 CPU 和 MMIO；复位释放后，8 路信号同时持续工作。

## CPU

`rv32_core` 是六级流水 `RV32I + Zicsr` 实现，流水级为 IF、ID、EX、数据请求、数据响应和 WB。除多级数据前递、加载-使用互锁、分支冲刷、自定义 `CRC16.B`、提交跟踪和性能事件外，还实现了机器态 CSR、`ECALL/EBREAK/MRET`、宽度访存与精确 trap。异常信息沿流水线传播到 WB，寄存器和 CSR 在 WB 更新。访存请求在数据请求级生效，读后清零等 MMIO 读取也属于副作用；若中断到来时响应级仍有已发出的访存，CPU 停住年轻指令并禁止新请求，先将这次访存推进到 WB 退休，再进入中断。已采样的中断请求与原因会保留到该边界，`mepc` 指向最后退休指令的下一 PC，返回后不会重放已生效访存。同步异常、MRET 和 FENCE.I 也阻止年轻访存越过其边界。无寄存器依赖的 JAL 在 ID 阶段提前重定向，JALR 和条件分支仍在 EX 阶段重定向。前递选择在 ID 阶段提前计算，避免把寄存器号比较器放在 EX 到 PC/ALU 的关键路径上。

实现的 CSR 为 `mstatus/misa/mie/mtvec/mscratch/mepc/mcause/mtval/mip/mhartid/mcycle/minstret`（含两个 64 位计数器的高半 CSR）。异常覆盖非法指令、M-mode ECALL、EBREAK、指令地址未对齐和 load/store 未对齐；异步中断覆盖 MSI 和 MTI。处理器始终运行在 M-mode，不包含 S-mode、MMU、PMP、PLIC 或 RV32M。

指令和数据存储器各为 64 KiB。取指端口在下降沿采样；EX 先寄存有效地址，再由数据请求级在上升沿访问同步 BRAM/MMIO，响应级保留对应元数据，下一上升沿才进入 WB。这样地址生成、外设译码和加载写回各自获得完整的 10 ns 周期。ROM 的第二只读端口映射到数据总线 `0x00000000..0x0000ffff`，供 C 运行时复制 `.data` 并访问 `.rodata`。RAM 位于 `0x10000000..0x1000ffff`，栈顶为 `0x10010000` 且保持 16 字节对齐。

## Machine timer 与 FreeRTOS

CLINT 使用标准地址：`msip=0x02000000`、`mtimecmp=0x02004000`、`mtime=0x0200bff8`。`mip.MTIP/MSIP` 直接反映外设电平；`mie` 与 `mstatus.MIE` 在提交边界共同决定是否进入中断。

`sw/freertos` 使用 GCC `-march=rv32i_zicsr -mabi=ilp32` 和官方 FreeRTOS Kernel V11.3.1 RISC-V port。启动代码设置 `gp/sp`、复制 `.data`、清零 `.bss`、安装 `mtvec` 后进入 `main()`。应用拆分为 `measurement_task`、`ui_task`、`uart_task` 和 `capture_task`：测量快照通过单元素覆盖队列发布，SINGLE/导出请求通过任务通知投递，UART 互斥量保护 shell、遥测和 CAP2 传输。采集任务完成 4096 点打包并用 `CRC16.B` 逐字节计算校验；1 kHz tick 由 CLINT MTI 驱动。

UART 硬件使用 1024 字节 RX FIFO，固件每次被调度后连续取数，排空后才延迟 1 ms。状态寄存器 `0x40001004` 的 bit0 为 TX 就绪、bit1 为 RX 非空、bit2 为粘滞溢出标志、bit3 为 RX 满；向 bit2 写 1 清除溢出。FIFO 满且无同时出队时丢弃新字节，保留队列中已有字节的顺序。

采集任务在等待期间每 1 ms 检查完成状态和任务通知。新的 SINGLE 会重新采集，已有导出请求跟随新采集；重复导出通知合并为一个待导出请求。`c` 取消并清除采集和待导出请求，返回 `ERR2 CANCELLED\n`。取消与其他通知同时到达时，取消优先。等待期限为 1000 ms 加上 `ceil(4096 × active_sample_div / 100000)` ms，超时停止采集并返回 `ERR2 TIMEOUT\n`，后续请求可重新启动。UART 互斥量保证错误行与 CAP2 帧不会交错；整帧发送完成后才处理新采集或取消。

当前配置包含任务、队列、互斥量、计数信号量、动态分配和任务通知；软件定时器、静态分配及部分任务管理 API 被关闭，事件组和流缓冲区源码未收录。测试结论限于该配置与当前四任务应用。

## 实时波形与深度采集

实时波形模块保存一段短采样历史。`AUTO`、`NORMAL` 和 `SINGLE` 模式将所选边沿对齐到 LED7；`FREE` 模式每 16 个样本发布一帧。`HOLD` 阻止新帧发布，`AUTO` 在长时间没有触发时强制刷新。`sample_div` 控制时基。

深度采集模块使用 4096×1 环形窗口。触发前保留 2048 点，触发后收集剩余样本，最后按时间顺序映射到 `0x40010000..0x40013fff`，触发位置固定为第 2048 点。边沿检测在 100 MHz 时钟域中进行，写入采样窗口的间隔仍由 `sample_div` 决定。

每次写控制寄存器启动采集时，硬件锁存时基、触发边沿、深度和预触发点数。采集中或完成后修改配置只影响下一次采集；本次锁存的边沿和分频分别通过只读寄存器 `0x40004024`、`0x40004028` 提供。控制寄存器的清除/重启优先于同拍采样与触发，防止取消后又被置为完成。

## 边沿测量

边沿测量硬件输出 `period_ticks`、`high_ticks`、`edge_age`、`valid` 和 `signal_present`。每个时钟计数为 10 ns，也可选择对最近四个周期求平均。超过动态超时时间仍未检测到有效边沿时，硬件会清除有效状态，避免软件继续使用过期读数。固件读取两次 `period_ticks`，只有两次结果一致时才更新缓存，并计算 `low_ticks = max(period_ticks - high_ticks, 0)` 和 `frequency_hz = floor(100000000 / period_ticks)`。32 位恢复除法因此由 CPU 执行，不再位于 FPGA 时序路径中；`MEA2` 和 CAP2 的协议字段保持不变。

## MMIO

| 基地址 | 外设 |
| --- | --- |
| `0x02000000` | CLINT `msip` |
| `0x02004000` | CLINT `mtimecmp` |
| `0x0200BFF8` | CLINT `mtime` |
| `0x10000000` | 64 KiB 数据 RAM |
| `0x40000000` | GPIO / 固件测试结果 |
| `0x40001000` | UART |
| `0x40002000` | 64 位计时器 |
| `0x40004000` | 深度采集控制/状态 |
| `0x40005000` | 实时波形 |
| `0x40006000` | 性能计数器 |
| `0x40007000` | 按钮/开关 |
| `0x40008000` | 八位数码管 |
| `0x40009000` | 边沿测量 |
| `0x40010000` | 4096 点采样窗口 |

## CAP2

UART 深度采集包包含 26 字节小端头、512 字节位打包样本和 2 字节 CRC16：

```text
magic[4] version[1] flags[1] count[2] sample_div[4]
trigger_index[2] period[4] high[4] frequency[4]
packed_samples[512] crc16[2]
```

FreeRTOS 固件在启动采集时保存测量快照，CAP2 的 `period`、`high` 和 `frequency` 来自这份快照；`flags` 和 `sample_div` 来自硬件为该次采集锁存的寄存器。修改当前开关和时基不会给旧样本重新标注。`low` 不单独写入 CAP2，客户端按 `period - high` 计算，结果下限为 0。

CRC 使用初值 `0xffff` 和多项式 `0xa001`，校验范围包括包头和数据区；固件逐字节执行 `CRC16.B`。

## 顶层与时序

`nexys_a7_top` 只暴露 100 MHz 时钟、复位、开关、按钮、16 个 LED、两颗 RGB LED、八位数码管、UART、8 位 `pmod_ja` 固定输出和唯一的测量输入 JB1。用于生成位流的工程显式列出所有 RTL 源文件。实现脚本写入位流前会检查布线后的建立和保持时序裕量，两者必须均为非负值；DRC 也不能含有 `Error` 或 `Critical Warning`。
