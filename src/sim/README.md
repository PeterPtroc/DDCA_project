# RTL 仿真验证

自动化验证分为六个测试平台：

- `tb_cpu_trace.v` 为 `isa_test`、`hazard_test` 和 `crc_test` 生成架构级指令提交跟踪。`rv32_ref.py` 与 `diff_trace.py` 对比 PC、指令、寄存器写回和存储操作的副作用。
- `tb_machine_mode.v` 运行自检固件，覆盖宽度访存、CSR 转发、ECALL、EBREAK、MRET、精确同步异常、mtime/mtimecmp、MSI 和 MTI。
- `tb_freertos_smoke.v` 运行 GCC 构建的官方 FreeRTOS RISC-V port，要求四个任务均启动、至少 4 次阻塞切换、至少 2 次定时器 tick，并拒绝任何意外 trap。
- `tb_freertos_scope.v` 验证 RTOS 版 UART shell、RUN/HOLD、测量/性能响应、SINGLE 深度采集、540 字节 CAP2 输出及 `CRC16.B` 校验。
- `tb_scope_core.v` 检查 8 路固定 JA 信号的两个完整周期，同时覆盖边沿测量、实时波形模式、触发、时基、4096 点深度采集、按钮事件、数码管寄存器和主要 RGB 状态。
- `tb_soc_realtime_scope.v` 模拟可选择的 JA4/JA9 到 JB1 跳线，并集成运行 CPU、`scope.S`、MMIO、UART、板载交互、边沿测量、实时波形和深度采集。

在仓库根目录运行以下命令，即可执行全部验证（FreeRTOS 烟测需要先生成 `build/hex/freertos.hex`）：

```powershell
.\scripts\test.ps1
.\scripts\test_freertos.ps1
```
