# RTL 仿真验证

自动化验证包含以下测试平台：

- `tb_cpu_trace.v` 为 `isa_test`、`hazard_test` 和 `crc_test` 生成架构级指令提交跟踪。`rv32_ref.py` 与 `diff_trace.py` 对比 PC、指令、寄存器写回和存储操作的副作用。
- `tb_machine_mode.v` 运行自检固件，覆盖宽度访存、CSR 转发、ECALL、EBREAK、MRET、精确同步异常、mtime/mtimecmp、MSI 和 MTI。
- `tb_precise_irq.v` 在两种 PC 实现中检查 MSI/MTI 的电平和单拍请求，覆盖连续访存前后 10 个中断落点，共 80 例。计数器检查存储和读后清零加载的请求数、退休数、返回后寄存器结果，防止丢失或重复副作用。
- `tb_uart_fifo.v` 检查 RX FIFO 的连续接收、顺序、回绕、溢出、溢出清除及满队列时同时入队/出队。
- `tb_freertos_smoke.v` 运行 GCC 构建的官方 FreeRTOS RISC-V port，要求四个任务均启动、至少 4 次阻塞切换、至少 2 次定时器 tick，并拒绝任何意外 trap。
- `tb_freertos_display.v` 在当前 FreeRTOS 固件下模拟 JA4/JA9 到 JB1 跳线，检查频率、周期、高/低电平、占空比与状态页。性能计数器注入 0、9、10、12345678、99999999、100000000 和 UINT32_MAX，验证十进制各位、进位、溢出横线及八位实际段码扫描；CPU 和 RTOS 显示任务正常运行。
- `tb_freertos_scope.v` 验证 RTOS 版 UART shell、连续命令、RUN/HOLD、测量/性能响应、真实分频的 SINGLE 深度采集、旧样本 CAP2 参数冻结、取消、无触发超时、后续采集恢复及 `CRC16.B` 校验。超时用例只提前 CLINT 时间，再由官方 port 逐次处理 tick；其他固件状态不强制修改。
- `tb_freertos_uart_burst` 复用上述测试平台，按实际分频 868（115200 波特率）连续发送 `s`、`m`，要求得到依次排列的 5 字节和 24 字节响应。
- `tb_scope_core.v` 检查 8 路固定 JA 信号的两个完整周期，同时覆盖边沿测量、实时波形模式、触发、时基、4096 点深度采集、按钮事件、数码管寄存器和主要 RGB 状态。

在仓库根目录运行以下命令，即可重建固件并执行全部验证：

```powershell
.\scripts\test_freertos.ps1
```

也可先运行 `scripts/build_freertos.ps1`，再运行 `scripts/test.ps1`。缺失 `build/hex/freertos.hex` 时，测试脚本直接失败，不能输出整体 PASS。
