# PtrocOS ELF loader

第 12 阶段在独立 `ptrocos_elf_soc` / `ptrocos_elf_nexys_a7_top` 中增加可写指令 RAM。原正确 CPU、原 `imem`、已有 SoC/top 和 `sw/freertos` 内核源码保持冻结。当前实现和最终验收仍在进行；以下已通过的单项检查不代表已完成板级时序、视频回归或实卡运行。

## 命令与构建

`mount` 后执行 `run /HELLO.ELF alpha "two words"`。`argv[0]` 是文件路径，最多使用现有 shell 的参数数量和行长；一次运行限制 5 秒，Ctrl+C 可取消。`elf info` 查看契约，`elf test` 从 ROM 内嵌的真实应用 ELF 依次加载并执行两次 Hello、非法指令程序和不调用 API 的死循环，检查 BSS 重载、异常和超时后返回 shell。内嵌诊断也使用相同的 ELF 校验与流式复制代码。

```powershell
.\scripts\build_ptrocos.ps1 -Firmware elf -ToolchainPrefix <riscv-none-elf prefix>
.\scripts\test_ptrocos_elf.ps1 -NativeOnly
.\scripts\test_ptrocos_app_memory.ps1
.\scripts\test_ptrocos_elf.ps1 -VideoRegression
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs elf
```

独立 ELF 固件保留文件、BMP、WAV、PTV 和 RGB565/黑白图形命令。当前 ROM 为 64,692 字节（text 64,680 + data 12），没有扩大原 64 KiB 容量。构建同时生成 `build/ptrocos_elf/apps/{hello,fault,loop}.elf`；`build/ptrocos_elf/ELF-SD.img` 提供 8 MiB FAT16 碎片测试镜像，含这三个应用和故意非法的 BAD.ELF，仅生成本地文件，未写物理卡。应用没有可选的 section 表，PT_LOAD/PT_NOTE 和指令字节完整保留。它们可以直接复制到 FAT 卡中。

## 内存与文件契约

| 范围 | 用途 |
| --- | --- |
| `0x00000000..0x0000ffff` | 既有内核 ROM，数据侧只读 |
| `0x00010000..0x00013fff` | 新增 16 KiB 应用代码 BRAM，数据侧用于加载 |
| `0x10000000..0x1000ffff` | 既有内核 BRAM |
| `0x80800000..0x808fefff` | 应用 DDR 数据 / BSS，1020 KiB |
| `0x808ff000..0x808fffff` | 应用 DDR 栈，4 KiB，初始 SP `0x80900000` |

代码和数据窗口与 DMA scratch、`0x81000000` RGB framebuffer、`0x81200000` 黑白视频环分离。每次运行先填充栈，退出检查栈底 64 字节；FreeRTOS 自身的内核栈检查仍启用。未加入 cache。

接受 ELF32、小端、ET_EXEC、EM_RISCV=243、版本 1、OSABI/ABI version 0、52 字节文件头、32 字节 program header，最多 8 项，e_flags=0。入口四字节对齐，其完整首条指令必须位于文件提供的可执行 PT_LOAD 范围。动态链接、解释器、TLS、压缩指令 ABI、浮点 ABI 和未知 program header 被拒绝；e_flags 本身无法证明文件中的每条指令均属 RV32IM，非法指令在执行时处理。

PT_LOAD 按虚拟地址递增且不重叠，必须可读，拒绝 W+X。代码窗口接受 R/RX，数据窗口接受 R/RW。`p_filesz <= p_memsz`，超出文件部分清零；使用 64 位边界运算，检查文件跨度、目标范围、对齐及 congruence。物理地址只允许 0 或等于虚拟地址。栈不得作为加载段。执行前使用固定 256 字节缓冲区复制，完整预校验失败时不写目标；取消、I/O 或输出错误时 `loaded=0`，运行入口不可用。部分复制的数据可能留在内存中。

文件必须包含唯一的自定义 PT_NOTE：name `PtrocOS\0`、type 1、descriptor 四个小端 u32：`[1,4096,0x00010000,0x80800000]`。该标记声明本机运行 ABI，未知版本被拒绝。段布局依据 [ELF gABI program headers](https://refspecs.linuxfoundation.org/elf/gabi4+/ch5.pheader.html)，RISC-V 标记与寄存器规则依据 [RISC-V ELF psABI](https://riscv-non-isa.github.io/riscv-elf-psabi-doc/)。本机地址范围和 PT_NOTE 是项目自己的约定。

## 执行与恢复

入口为 `int entry(const struct ptrocos_app_api *, int argc, const char *const *argv)`，API 提供版本号、有限长度文本输出、让出调度、取消状态。使用提供的 linker/CRT，以 RV32IM ILP32、`-msmall-data-limit=0 -mno-relax` 和 linker `--no-relax` 编译。应用须保持 gp、tp 和机器 CSR 不变，标准 SP 为 16 字节对齐；不提供 Linux syscall、动态加载或进程隔离。应用运行在受信任 M-mode，段 flags 校验不构成硬件访问权限。

加载时串行化应用窗口与 storage；执行前关闭文件并释放 storage 锁，防止应用运行长期占用卷。汇编保存内核 SP、RA、gp、tp、s0..s11，切换到 DDR 栈并保留调度。正常退出、异常或超时都使用保存的内核帧恢复。

冻结的 FreeRTOS RV32 port 将 31 字上下文放在当前栈，word 0 是恢复 PC，word 30 是 critical nesting；同步异常回调的 PC 已加 4。ELF 专用异常处理和 tick hook 只修改当前应用任务的已保存上下文，使其返回 ROM 恢复入口。tick hook 在应用代码 PC、critical nesting 为 0 时检查取消/超时；在 ROM API 操作期间不强行中断，以免丢失内核锁。其他任务异常仍触发既有 panic。应用破坏 SP、gp/tp、CSR、内核内存或违反 ABI 不在可恢复保证内。

原 `imem` 在下降沿取指，非零高 16 位地址输出 NOP。新 app RAM 的两个 BRAM 端口均使用下降沿，数据请求经 held-payload mailbox 到相反边沿，并等待同步 RAM 结果。两边属于同一 100 MHz 时钟，保留正常半周期 setup/hold 分析，不添加异步时钟切断。OOC 综合已确认 4 个 RAMB36，setup +3.136 ns / hold +0.041 ns；这只是独立综合估计，板级 routed gate 仍须通过。

## 已完成单项检查与待验

独立 C 解码/复制检查：916 checks，397,865 个复制字节、244,443 个清零字节，覆盖 canary、完整预校验、文件和内存边界、note/flags、取消、I/O、输出失败和重试。指令 RAM unit：9,221 transactions / 4,608 stores / 53,258 fetches，含全 4,096 字、字节 lane、地址别名拒绝、reset 与重复写保护。

真实 FatFs + diskio + SD 驱动的主机 SPI 模型：96 checks，FAT12/16/32、MBR 分区、碎片链，按独立 ELF 字节核对每个复制/BSS/gap/canary；包括取消、拔卡、CRC 和重试。首轮两种 PC 样式 SoC 均通过实际 RV32IM/FreeRTOS 执行，14,027,997 cycles、2,770,737 app retired、28 SD reads、138 timer IRQ、237 yields。最终两种 PC 样式也通过相同测试，并对每种样式的 9 次调用逐次独立比对恢复后的 RA、SP、gp、tp、s0..s11。ELF 固件视频回归和独立板级实现仍在进行。

实卡 ELF/Bad Apple、VGA 显示器和模拟音频仍未验收；当前 SD 报 no-card，显示器未连接。键盘实物测试由用户明确延期。最终结果将在 `ptrocos-elf-validation.json` 中记录，不将模型测试或 UART 内嵌诊断等同于实卡运行。
