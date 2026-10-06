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

## 验证

复现入口：`scripts/test_ptrocos_files.ps1`。结果、覆盖范围与产物 SHA 见 [ptrocos-files-validation.json](ptrocos-files-validation.json)。统一构建、命令入口和物理待验项见 [开发说明](ptrocos-development.md)。
