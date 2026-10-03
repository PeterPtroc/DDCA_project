# FreeRTOS RV32I firmware

本目录包含本 SoC 的启动代码、链接脚本、板级支持和多任务应用。`kernel/` 是从官方 [FreeRTOS-Kernel V11.3.1](https://github.com/FreeRTOS/FreeRTOS-Kernel/tree/V11.3.1) 固定提取的最小源码集合，版本提交为 `3a22924e0a9ddbbc8b0758881c33b3422a5cc20d`，保留原 MIT 许可证与文件头。

需要任一裸机 RISC-V GCC 工具链，其命令前缀可为 `riscv32-unknown-elf`、`riscv-none-elf` 或 `riscv64-unknown-elf`：

```powershell
.\scripts\build_freertos.ps1
# 或显式指定：
.\scripts\build_freertos.ps1 -ToolchainPrefix C:\toolchains\bin\riscv-none-elf
```

输出包括 `build/freertos/freertos.elf`、map/listing 和 `build/hex/freertos.hex`。完整仿真回归使用：

```powershell
.\scripts\test_freertos.ps1 -ToolchainPrefix C:\toolchains\bin\riscv-none-elf
```

编译目标固定为 `-march=rv32i_zicsr -mabi=ilp32`；项目不依赖 RV32M、浮点、S-mode、MMU、PMP 或 PLIC。

应用包含 `measurement_task`、`ui_task`、`uart_task` 和 `capture_task`。它保留 `s/m/r/h/1/d/p` UART 协议、100 ms 可选遥测和 CAP2 深度采集格式；队列发布测量快照，任务通知触发 SINGLE/导出，互斥量串行化 UART，CAP2 CRC 由 CPU 的 `CRC16.B` 指令计算。
