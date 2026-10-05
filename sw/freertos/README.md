# FreeRTOS RV32I firmware

本目录包含本 SoC 的启动代码、链接脚本、板级支持和多任务应用。`kernel/` 是从官方 [FreeRTOS-Kernel V11.3.1](https://github.com/FreeRTOS/FreeRTOS-Kernel/tree/V11.3.1) 固定提取的最小源码集合，版本提交为 `3a22924e0a9ddbbc8b0758881c33b3422a5cc20d`，保留原 MIT 许可证与文件头。

数码管由 `board_display_decimal()` 转换为八位十进制，超出八位时显示 `--------`。

在 64 位 Windows 上使用 PowerShell 5.1 或 7，并安装 Python 3、将 `python.exe` 加入 PATH 后，只需运行：

```powershell
.\scripts\build_freertos.ps1
```

脚本自动调用 `scripts/setup_toolchain.ps1`，按 `tools/toolchain.json` 固定的版本和 SHA-256 下载、校验并安装 xPack RISC-V GCC **15.2.0-1**。首次运行需访问 GitHub，ZIP 约 444 MiB；安装目录为 `tools/.local/xpack-riscv-none-elf-gcc-15.2.0-1/`，ZIP 缓存在 `tools/.local/downloads/`。后续编译直接复用本地工具链，不访问网络；安装目录缺失或不完整时，会从已校验的缓存 ZIP 重新解压。下载中断后可直接重跑，未完成的下载不会被当作有效缓存。这些文件均由 Git 忽略，无需提交二进制工具链。

也可单独运行 `.\scripts\setup_toolchain.ps1` 提前安装。需要更换固定版本时，同步更新 `tools/toolchain.json` 中的版本、官方 ZIP 地址和 SHA-256。

使用自备的裸机 RISC-V GCC 时，显式指定前缀即可跳过自动安装；也可设置 `RISCV_TOOLCHAIN_PREFIX` 环境变量，显式参数优先。前缀不包含末尾的 `-gcc` 或 `.exe`，例如：

```powershell
.\scripts\build_freertos.ps1 -ToolchainPrefix C:\toolchains\bin\riscv-none-elf
```

输出包括 `build/freertos/freertos.elf`、map/listing 和 `build/hex/freertos.hex`。完整仿真回归使用：

```powershell
.\scripts\test_freertos.ps1
```

编译目标固定为 `-march=rv32i_zicsr -mabi=ilp32`；项目不依赖 RV32M、浮点、S-mode、MMU、PMP 或 PLIC。

应用包含 `measurement_task`、`ui_task`、`uart_task` 和 `capture_task`。它保留 `s/m/r/h/1/d/p` UART 协议、100 ms 可选遥测和 CAP2 深度采集格式；队列发布测量快照，任务通知触发 SINGLE/导出，互斥量串行化 UART，CAP2 CRC 由 CPU 的 `CRC16.B` 指令计算。
