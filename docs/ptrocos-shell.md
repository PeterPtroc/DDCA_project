# PtrocOS TTY 与 shell

UART 与 VGA/PS2 各有独立队列、编辑状态和历史，使用冻结的 FreeRTOS 11.3.1 内核与独立配置。CPU 100 MHz，tick 1 kHz；heartbeat/input/两个 TTY/idle 共五个任务。堆 24 KiB，完整存储及 ELF 固件的两个 TTY 栈各为 1536 个 32 位字。

命令行上限 63 字节、8 个参数（含命令名），支持单/双引号和反斜杠转义。支持插入、Backspace/Delete、方向/Home/End、四条历史、Tab 唯一命令补全及 Ctrl+A/E/B/F/U/K/W/L。Ctrl+C 取消当前命令；超长行或输入丢失时丢弃整行，防止执行截断指令。没有管道、重定向和变量展开。

| 命令 | 功能 |
| --- | --- |
| `help`、`echo`、`clear`、`uname` | 帮助、参数输出、清屏、系统信息 |
| `uptime`、`mem`、`tasks` | 调度、输入丢弃、堆及任务栈余量 |
| `video`、`kbd` | 文本控制器及 PS/2 状态 |
| `sleep 0..60000` | 可取消的毫秒等待 |
| `ddrtest` | DMA 复制 256 字并核对 CRC，成功为 `0000f364` |

DMA scratch 为 `0x80001000..0x800013ff` 与 `0x80002000..0x800023ff`。文件、图形、音视频和应用命令见 [开发说明](ptrocos-development.md)。共享资源由互斥量管理；取消先完成已发出的总线事务，再释放所有权。

复现：`scripts/test_ptrocos_shell.ps1`；板卡：`python tools/ptrocos_shell_test.py --port COM9`。原阶段仿真记录见 [shell 验收](ptrocos-shell-validation.json)，后续文件固件已补齐 UART 实机验收，见 [文件验收](ptrocos-files-validation.json)。PS/2 到 VGA TTY 自动测试来自仿真，物理键盘按用户要求延期。
