# PtrocOS 开发与验证

实验开发基于 `80cc06f144e8c954c662490dbeac25e489bfda8d`，在隔离 worktree 的 `codex/ptrocos-evolution` 分支验证后提交到 `PtrocOS`，提交说明沿用 `[feat]`、`[fix]` 等中文格式。原有 `rv32_core`、CPU 辅助模块、生产 SoC、板级顶层、约束和固件构建流程均保留。新增功能使用独立模块与验证入口，现有示波器工程继续使用原 CPU。

## 开发顺序

按以下顺序逐阶段验收。具体状态与验收条件保存在 [ptrocos-roadmap.json](ptrocos-roadmap.json)。

1. 保留正确 CPU 基线。
2. RV32M 与独立 ISA 测试。
3. DDR2 与 DMA。
4. VGA text mode 与 PS/2 keyboard。
5. PtrocOS TTY 与 shell。
6. SD 与 FatFs。
7. `ls`、`cat`、`hexdump`。
8. DDR framebuffer 与 VGA graphics。
9. BMP 与 WAV。
10. 自定义视频与 Bad Apple。
11. 根据实际性能测量结果评估 I/D cache。
12. 后续实现 ELF loader。

## RV32M 实现

`rv32im_core` 从基线复制而来，通过 `rv32im_decoder` 扩展原译码器；原 `decoder` 文件没有修改。`misa` 返回 `0x40001100`。`rv32m_unit` 实现 `MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU`，普通运算使用 32 次迭代，除零提前完成。RTL 中没有组合乘法或除法运算符。

乘除法在 EX 阶段启动。CPU 保存已前递的操作数，冻结 IF/ID/EX，允许更老指令和已发出的访存正常退休。运算结果完成后只向下游送出一次。更老的异常、中断、MRET 或 FENCE.I 引起提交重定向时，复位乘除单元以取消推测执行；已产生 MMIO 副作用的指令仍先退休。

除法向零截断，余数符号跟随被除数。除零返回全 1 商和原被除数作为余数；`INT_MIN / -1` 返回 `INT_MIN`，余数为零。语义依据 [RISC-V M 扩展规范](https://docs.riscv.org/reference/isa/v20240411/unpriv/m-st-ext.html)。

## 运行验证

在实验 worktree 根目录运行：

```powershell
.\scripts\test_rv32m.ps1 -VivadoBin D:\xilinx\Vivado\2024.2\bin
```

测试无需 FreeRTOS 固件。脚本首先检查原 CPU 与生产集成文件相对基线无改动，再生成固定随机种子的测试输入。

| 验证 | 范围 |
| --- | --- |
| 运算单元 | 5,248 组边界与随机向量；忙期间输入变化、新请求、复位取消与完成脉冲 |
| 独立 ISA | 自检固件和 Python 整数算术参考模型；两种 PC 实现各对比 10,001 条提交记录 |
| 冒险 | ALU 到 M、load 到 M、连续 M、目的与源重叠、x0、依赖分支与存储 |
| 多周期中断 | 648 例；MSI/MTI、电平/脉冲、81 个落点、两种 PC 实现、读后清零 MMIO |
| 推测执行取消 | ECALL、非法指令和 FENCE.I 后的年轻 M 指令取消；两种 PC 实现 |
| 兼容性 | 原 ISA、hazard、CRC 提交差分；机器态固件和 80 组精确中断 |

参考模型使用 Python 任意精度乘法与整数除法，RTL 使用移位加法和恢复除法。两者不共用算法。机器态测试仅在生成的实验固件中将 `misa` 期望改为 I+M，原测试固件保持原样。

生成的固件、向量与提交记录位于 `build/rv32m/`。原版完整回归使用 `scripts/test.ps1`，2026-10-05 在实验 worktree 中运行通过；日志为 `build/baseline-regression.log`，其 FreeRTOS HEX 从原工作区复制。

独立核的综合与布线检查入口如下。该检查仅约束 CPU 内部寄存器路径，是核级 OOC 验证；接入板级时仍需重新检查 BRAM、MIG、时钟与接口路径。2026-10-05 在 Vivado 2024.2 和 `xc7a100tcsg324-1` 上，100 MHz 内部路径 WNS 为 +0.261 ns，WHS 为 +0.055 ns。报告位于 `build/rv32m/timing/`，验证输入 SHA-256 位于 `rv32m-validation.json`。

```powershell
vivado -mode batch -source scripts/check_rv32m_timing.tcl
```

## DDR2 接口设计要求

DDR2 IP 已生成，CPU 等待握手、AXI 桥、DMA、仲裁和跨时钟通路已分别通过逻辑仿真，尚未组成实验板级 SoC。`rv32im_mem_core` 从已验证的 RV32IM 核独立复制，原 RV32I 与 RV32IM 核均保持原样。等待期间保持请求与操作数稳定，禁止重复写入，允许较老指令退休；中断等待未完成的访存及其退休。总线错误产生 load/store access fault，`mtval` 记录原访问地址。

`ddr2_axi_word_bridge` 将 32 位请求转换为对齐的单个 128 位 AXI beat，因为官方 MIG 配置关闭 narrow burst。写掩码保留相邻字节，等待 AW/W 和 B/R 响应后才返回完成。DDR 地址范围为 `0x80000000..0x87ffffff`，越界请求在桥内拒绝。

`word_bus_cdc` 使用单个待处理请求和 request/completion toggle，在 CPU 与 MIG 时钟域之间传递保持稳定的数据。两域必须在失去校准时共同复位，并分别同步释放复位。逻辑仿真不能替代板级 CDC 与时序检查。`word_bus_arbiter` 在 CPU 和 DMA 之间轮流仲裁，将授权保持到请求完成。

`dma_copy` 复制对齐的 DDR 数据字，拒绝重叠区域、未对齐、越界和长度溢出。启动时锁存配置；忙时重新配置或重复启动不替换当前任务。取消请求等待当前总线事务完成：读阶段取消不启动写入，写阶段取消先完成当前写入。DMA 也处理总线错误并支持恢复。后续 framebuffer、SD 和音频将复用内存通路；开始 cache 前先完成这些路径并测量实际带宽。

```powershell
.\scripts\test_memory_interface.ps1 -VivadoBin D:\xilinx\Vivado\2024.2\bin
```

该脚本已通过两种 PC 实现各 10,001 条带等待的 ISA 提交差分、648 组带等待的中断测试、延迟 load/store access fault 与恢复、135 组 AXI 请求、64 组异步 mailbox 请求、40 组竞争仲裁请求，以及 DMA 的复制、配置冻结、非法参数、取消和错误恢复测试。日志为 `build/memory-interface-regression.log`。它不包含真实 MIG 存储器模型或板卡校准测试。

板卡内存配置依据 [Digilent Nexys A7 参考手册](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf) 与 [官方 MIG 配置](https://github.com/Digilent/vivado-boards/blob/master/new/board_files/nexys-a7-100t/D.0/1.3/mig.prj)。实际 MIG 校准、DDR 压力测试、显示、键盘、SD 和音频都需要独立板级验收。

官方 MIG 配置及 MIT 许可证保存在 `third_party/digilent/`，配置文件保持原样并记录 SHA-256。独立运行 `vivado -mode batch -source scripts/create_ddr2_ip.tcl` 可在 `build/ptrocos_ddr2/` 生成 MIG；已确认 IP 目标器件为 `xc7a100tcsg324-1`，AXI 数据宽度为 128 位。当前还没有实验板级位流或 DDR2 校准结果。
