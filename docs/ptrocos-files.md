# PtrocOS 文件命令

第 7 阶段在 `storage` 固件中加入 `ls`、`cat`、`hexdump`。沿用已验证的 SD SPI、FatFs R0.16 与 FreeRTOS；CPU、RTL、板级约束和原 FreeRTOS 内核相对第 6 阶段提交 `764dc9f` 均未修改。键盘实物验收按用户要求延期，FPGA 检测已恢复，新位流已加载，UART shell 实机验收通过；SD 控制器报告 `no-card`，实卡文件验收保留待确认。

## 使用

先执行 `mount`。路径从卷根目录解析，支持 `/SUBDIR/FILE.TXT`、`0:/FILE.TXT`；带空格的路径用引号包围。TTY 每行最多 63 字节，当前编辑器接受 ASCII 输入。FatFs 的 UTF-8 文件名与 255 UTF-16 单元长文件名支持保持开启，UART 的 `ls` 可输出这些文件名；当前 TTY 无法直接键入非 ASCII 路径。

| 命令 | 行为 |
| --- | --- |
| `ls [path]` | 默认列卷根目录；指定目录列内容，指定文件显示该文件。每行依次为 `d/f`、十进制字节数、名称，按 FAT 目录顺序输出，不排序 |
| `cat <path>` | 流式输出完整文件，UART 字节保持原样，包括 NUL、CR/LF、ESC 与高位字节，不添加末尾换行 |
| `hexdump <path> [offset] [count]` | 偏移和长度均为无符号十进制；默认偏移 0、长度 256，最大长度 4096。每行 16 字节，8 位十六进制地址、字节值及 ASCII 栏，不压缩重复行 |
| `fscheck <path>` | 保留第 6 阶段的整文件字节数与 CRC16 检查 |

```text
mount
ls
ls /SUBDIR
cat '/notes/read me.txt'
hexdump /SUBDIR/NESTED.BIN 240 32
umount
```

空文件的 `cat/hexdump` 不输出正文；长度 0 或偏移超过 EOF 的 `hexdump` 也不输出正文。非法参数先报 usage，不访问 SD 卡。路径不存在、读取失败及 CRC 错误保留 FatFs 数字错误码和 SD 错误名称。

`cat` 的原始字节由所在 TTY 的输出通路处理。UART 原样发送；VGA 沿用文本控制台的 ASCII 字形与换行、回车、退格、Tab 行为，无法绘制 UTF-8 字形。无换行文件输出后，提示符会在当前行重新绘制，UART 原始日志仍保留全部正文。二进制文件可用 `hexdump` 查看，目录名称中的控制字符显示为 `\xNN`。

## 取消与资源

两个 TTY 的文件系统命令共用外层互斥锁，挂载和卸载也受该锁保护。等锁期间可用 Ctrl+C 取消，不改变当前持有者的取消源。文件与目录对象在正常结束、取消和错误路径中均关闭。

`cat` 使用 512 字节读缓冲；`hexdump` 使用 16 字节读缓冲及 81 字节行缓冲；`ls` 使用单个 `FILINFO`。每个块或目录项后让出 CPU，输入任务与 heartbeat 保持运行。输出阶段取消保留可用挂载；SD 事务中取消、拔卡或 CRC 错误使驱动失效时，同时清除应用的挂载状态，后续命令提示重新 `mount`。这些文件命令只读，不创建、写入或格式化文件。

## 验证入口

```powershell
python sw/tools/check_storage_commands.py
python sw/tools/check_storage_uart_tool.py
python sw/tools/check_tty.py
.\scripts\build_ptrocos.ps1 -Firmware storage -ToolchainPrefix <riscv-none-elf前缀>
.\scripts\test_ptrocos_files.ps1
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs storage
```

验收结果：文件命令原生 450 项、SD 驱动 132 项、FatFs 回归 306 项、TTY 20,286 个事件、串口工具边界 13 项均通过。SoC 两种 PC 实现分别完成 15,726,193 / 7,725,654 个周期；UART TTY 最低剩余栈为 905 words，heap 最低剩余 7968 bytes。最终 WNS +0.110 ns、WHS +0.038 ns、WPWS +0.206 ns，各负裕量总和为零，DRC 无 Error/Critical Warning。

原生测试编译实际 `storage_commands.c`、FatFs、diskio、SD 驱动及命令解析器，只替换板级传输和调度接口。独立 FAT12/16/32、MBR 镜像验证目录与碎片文件，Python 从字面文件数据计算预期输出；测试覆盖全 256 字节值、空文件、跨扇区文本、UTF-8/LFN、偏移越界、随机长度、4096 字节上限、错误参数、并发读取、持锁等待取消、输出取消、事务取消、CRC 错误、拔卡与重新挂载。长文件名测试通过已验证的 FatFs 写接口建立文件，再独立解码 FAT 和目录确认内容；命令本身不写卡。

完整 SoC 测试使用真实 RV32IM/FreeRTOS 固件、引脚级 SD 模型、延迟 12 ns 的 MISO、独立稀疏 AXI 存储器和三组时钟。两种 PC 实现分别挂载 SDHC/FAT16 和 SDSCv1/FAT12，从 UART 引脚逐字节核对 1100 字节二进制、690 字节碎片文本及空文件；完整比较带非对齐偏移、尾行填充的 hexdump。PC 实现 0 额外检查取消、拔卡、CRC 错误及重新挂载。也检查 SD 无写命令、SPI 恢复空闲、调度进度和输入无丢失。

`check_storage_uart_tool.py` 用模拟串口检查上板工具的原始字节边界，覆盖文件内含提示符、任意分块、空文件、无末尾换行及错误字节拒绝；这项测试不代表硬件验收。运行结果、源文件与产物 SHA-256 见 [ptrocos-files-validation.json](ptrocos-files-validation.json)。第 6 阶段的历史产物已按原记录哈希保存在主工作区 `build/ptrocos-stage6-snapshot/`，当前 `storage` 构建路径用于第 7 阶段。

本阶段发现旧 Vivado 工程的 `reuse` 分支未补装第 6 阶段的 post-place ROM 地址扇出优化。构建脚本现会先补齐该 hook；通过真实工程属性读回核对，并从本次固件的 placed checkpoint 重跑优化、路由和既定时序/DRC 门槛。首次 +0.062 ns 的结果及最终报告均保留。优化只复制物理寄存器，不修改 CPU RTL、频率或 ROM 时钟相位。

## 上板结果与待验收

2026-10-06 11:42 已将本阶段位流加载到 JTAG `210292B7F710A` 的 `xc7a100t_0`。COM9 上 UART shell 验收通过，包括编辑、历史、补全、引号/转义、行长边界、队列丢失恢复、Ctrl+C、三轮 DDR/DMA CRC、heap/栈及定时器和 VGA 帧计数进度。此测试主动制造一次输入队列溢出，记录的 `input_dropped=1` 属于该测试；SoC 文件命令测试未丢输入。

`mount` 返回 `FatFs error=3 SD=no-card`，`sdinfo` 显示状态 `0`、ready/read/write/exchange 均为 `0`；实卡存在与检测极性尚未确认。板上 `ls/cat/hexdump` 的未挂载提示及 `umount` 恢复已检查，没有实际 SD 字节交换或文件读取。键盘和显示器实物验收继续延期。

确认已有 FAT 卡并能挂载后，使用与卡上文件完全相同的本地原件进行只读验收：

```powershell
python tools/ptrocos_storage_test.py --port COM9 --file /HELLO.TXT --expected C:\data\HELLO.TXT --files
```

工具比较 `fscheck` 的字节数与 CRC、`ls` 的文件大小、`cat` 的每个原始字节及前 256 字节的 hexdump，并检查 heap、任务栈和调度进度。实卡初始化、板级 SD 电源与检测极性、电气时序、显示效果仍待验收。键盘实物验证保持延期。
