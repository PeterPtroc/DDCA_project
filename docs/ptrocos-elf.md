# ELF 加载与应用运行

独立 `ptrocos_elf_soc` 与 `ptrocos_elf_nexys_a7_top` 加入可写指令 RAM。原正确 CPU、原 imem、已有 SoC/top 和 FreeRTOS 内核保持冻结；完整固件继续提供文件、图形、BMP、WAV 和 PTV 命令，没有 cache。

```text
mount
run /HELLO.ELF alpha "two words"
elf info
elf test
```

`run` 加载文件、清零 BSS 后运行，正常返回后恢复 shell；默认限时 5 秒，Ctrl+C 可取消。`elf test` 用 ROM 内嵌的真实应用 ELF 检查两次 Hello/BSS 重载、非法指令和非协作死循环超时。生成的应用为 `build/ptrocos_elf/apps/{hello,fault,loop}.elf`。

| 范围 | 用途 |
| --- | --- |
| `0x00000000..0x0000ffff` | 原内核 ROM |
| `0x00010000..0x00013fff` | 16 KiB 应用代码 BRAM |
| `0x10000000..0x1000ffff` | 内核 BRAM RAM |
| `0x80800000..0x808fefff` | 应用数据/BSS，1020 KiB |
| `0x808ff000..0x808fffff` | 应用栈，4 KiB，SP 初值 `0x80900000` |

接受 ELF32、小端、ET_EXEC、EM_RISCV=243、版本 1、OSABI/ABI version 0、e_flags=0；文件头 52 字节，program header 32 字节，最多 8 项。入口四字节对齐且完整首条指令位于文件提供的可执行 PT_LOAD。PT_LOAD 按地址排序、不重叠，检查 64 位边界、文件长度、对齐、paddr、可读属性和目标窗口；拒绝 W+X、可执行数据段、可写代码段和占用栈的段。拒绝动态链接、解释器、TLS、未知 program header 及压缩/浮点 ABI。

必须含唯一 PT_NOTE：name `PtrocOS\0`、type 1、descriptor 四个 u32 `[1,4096,0x00010000,0x80800000]`。完整预校验后用固定 256 字节缓冲复制并清零 BSS；失败或取消时 `loaded=0`，残留字节不可用于执行。ELF flags 无法证明每条指令的 ISA，运行时非法指令仍会处理。标准依据 [ELF gABI](https://refspecs.linuxfoundation.org/elf/gabi4+/ch5.pheader.html) 与 [RISC-V psABI](https://riscv-non-isa.github.io/riscv-elf-psabi-doc/)，地址与 note 为本项目约定。

入口为 `int entry(const struct ptrocos_app_api *, int argc, const char *const *argv)`，API 提供文本输出（每次最多 512 字节）、yield 和取消状态。使用提供的 CRT/linker，以 RV32IM ILP32、`-msmall-data-limit=0 -mno-relax` 和 `--no-relax` 构建。应用必须保持 gp、tp、机器 CSR 和内核内存不变。这是受信任 M-mode ABI，没有 MMU、进程隔离、Linux syscall 或动态链接。

加载时持有应用窗口与 storage 锁，执行前关闭文件并释放 storage。调用保存内核 SP、RA、gp、tp、s0..s11，切换到 DDR 栈；正常退出、异常、超时均恢复原帧。栈底保留 64 字节 guard。ELF 专用 tick/异常钩子仅修补应用任务保存的上下文，在 ROM API 或 RTOS critical section 内不强制退出，防止丢失锁；违反上述 ABI 的应用不承诺恢复。

应用 BRAM 两个端口均下降沿取指/读写，共 4 个 RAMB36。mailbox 两端属于相关的同一 100 MHz 时钟，保留正常半周期 setup/hold，没有增加异步 cut。ROM 为 64,692 字节，仍在原 64 KiB 容量内。

原生解码 916 项、真实 FatFs/SD 模型 96 项、指令 RAM 单元 9221 次事务通过；两种 PC 样式 SoC 均独立核对 9 次寄存器恢复。最终板级 setup/hold/pulse 为 +0.268/+0.018/+0.206 ns，DRC 无 Error/Critical Warning；COM9 的 7 项 UART 检查通过。补充长视频回归的状态单独记录，不将未完成的运行计作 PASS。

复现入口：`scripts/test_ptrocos_elf.ps1`、`scripts/test_ptrocos_app_memory.ps1`；应用构建由 `scripts/build_ptrocos_apps.ps1` 完成。详细范围见 [ELF 验收](ptrocos-elf-validation.json)，统一构建和物理待验项见 [开发说明](ptrocos-development.md)。
