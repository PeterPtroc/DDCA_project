# RTL 仿真验证

课程设计的自动化验证分为三个测试平台：

- `tb_cpu_trace.v` 为 `isa_test`、`hazard_test` 和 `crc_test` 生成架构级指令提交跟踪。`rv32_ref.py` 与 `diff_trace.py` 对比 PC、指令、寄存器写回和存储操作的副作用。
- `tb_scope_core.v` 检查 8 路固定 JA 信号的两个完整周期，同时覆盖边沿测量、实时波形模式、触发、时基、4096 点深度采集、按钮事件、数码管寄存器和主要 RGB 状态。
- `tb_soc_realtime_scope.v` 模拟可选择的 JA4/JA9 到 JB1 跳线，并集成运行 CPU、`scope.S`、MMIO、UART、板载交互、边沿测量、实时波形和深度采集。

在仓库根目录运行以下命令，即可执行全部三层验证：

```powershell
.\scripts\test.ps1
```
