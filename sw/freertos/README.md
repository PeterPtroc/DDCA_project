# 固件构建入口兼容说明

本路径保留用于根 README 快速启动中的链接。旧示波器应用已移除，当前固件位于 `sw/ptrocos`，FreeRTOS 内核位于 `third_party/freertos/kernel`，启动与运行时位于 `sw/ptrocos/os`。

`build_freertos.bat` 和 `scripts/build_freertos.ps1` 现在调用 `scripts/build_ptrocos.ps1 -Firmware elf`，输出完整 RV32IM + Zicsr PtrocOS 固件，并生成 `build/hex/freertos.hex` 兼容副本。

工具链固定为 xPack RISC-V GCC 15.2.0-1，版本与 SHA-256 见 `tools/toolchain.json`。首次运行自动下载并校验，之后复用 `tools/.local/`。自备工具链可传 `-ToolchainPrefix C:\toolchains\bin\riscv-none-elf`，或设置 `RISCV_TOOLCHAIN_PREFIX`；显式参数优先。

构建、下载、测试与使用见 [PtrocOS 开发说明](../../docs/ptrocos-development.md)。
