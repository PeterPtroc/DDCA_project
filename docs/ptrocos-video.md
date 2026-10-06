# 自定义视频与 Bad Apple

第 10 阶段增加本地 PTV1 转换器与 `video` 固件。素材在主机上转换成 160×120 黑白位图，板上 VGA 以 4 倍整数放大到 640×480；单声道 PCM 与对应视频帧顺序交错存储。CPU 和 FreeRTOS 内核保持冻结，现有 RGB565、BMP、WAV 与文件命令继续保留。独立软件测试、图形单元仿真、两种 PC 实现的完整 SoC 仿真、板级时序与 UART 诊断已通过；实卡和屏幕播放尚未验证。完整记录与 SHA-256 清单见 [ptrocos-video-validation.json](ptrocos-video-validation.json)。

## 使用

```powershell
python sw/tools/convert_ptrocos_video.py <本地原视频> BADAPPLE.PTV --fps 15 --audio-rate 16000
.\scripts\build_ptrocos.ps1 -Firmware video -ToolchainPrefix <riscv-none-elf前缀>
.\scripts\test_ptrocos_video.ps1
vivado -mode batch -source scripts/build_ptrocos_bitstream.tcl -tclargs video
vivado -mode batch -source scripts/program_ptrocos.tcl -tclargs localhost:31234/xilinx_tcf/Digilent/210292B7F710A video
python tools/ptrocos_video_test.py --port COM9
```

将 PTV 文件放到支持的 FAT SD 卡后，使用 `mount` 与 `play /BADAPPLE.PTV`。`video info` 报告最近一次播放的读入、显示、丢帧、播放时间、最大延迟与音频采样率；`video test` 生成 4 帧、15 fps、8000 Hz 的诊断片段，无需 SD 卡。原 `video` 无参数命令仍显示文本控制器状态。`gfx off` 返回文本模式，Ctrl+C 取消播放并清空音频 FIFO。

转换器支持 10～30 fps，音频采样率 8000～16000 Hz，最大一小时。原始视频由 FFmpeg 解码、调整帧率、保持宽高比缩放并填黑；阈值默认 128。音频混合为单声道无符号 16 位小端 PCM，长度按视频时间截断或补中点静音。`--silent` 生成无音轨视频。转换使用磁盘临时文件和固定帧缓冲，不将整个视频装入 RAM；源文件在处理前后核对 SHA-256。已有输出默认拒绝覆盖，明确指定 `--force` 才原子替换。FFmpeg 和 NumPy 是主机转换/验证工具所需依赖，固件不需要它们。

## PTV1 格式

固定 32 字节小端文件头，不包含索引表。所有字段都经过检查，文件长度必须与声明的帧数和音频长度完全一致，尾部额外数据也拒绝。

| 字节偏移 | 类型 | 内容 |
| --- | --- | --- |
| 0 | 4 bytes | `PTV1` |
| 4 | u16 | 头长度，固定 32 |
| 6 | u16 | flags，0=无音轨，1=有音轨 |
| 8 / 10 | u16 | 宽 160 / 高 120 |
| 12 | u32 | 整数 fps，10～30 |
| 16 | u32 | 非零帧数，时长最多一小时 |
| 20 | u32 | 无音轨为 0；否则 8000～16000 Hz |
| 24 | u32 | 每帧位图字节数，固定 2400 |
| 28 | u32 | reserved，必须为 0 |

第 i 帧从 0 开始：先保存 2400 字节位图，再保存 `floor((i+1)*rate/fps)-floor(i*rate/fps)` 个 PCM 采样。位图每行 20 字节，左边像素在字节 bit0，0=黑、1=白；文件内行紧邻，没有 DDR padding。PCM 为单声道 unsigned16，小端，32768 为静音。文件总长度为 `32 + frames*2400 + floor(frames*rate/fps)*2`，长度计算使用 64 位整数。音视频完全按文件顺序读取，不在两个文件之间反复寻址。

## 帧缓冲与调度

DDR 帧环从 `0x81200000` 开始，8 个槽，每槽 4096 字节；160×120 位图使用 stride 32 字节，共 3840 字节，后 12 字节行 padding 写零。开始播放选取当前 front 的下一个槽；写入前检查不能覆盖正在扫描的 front。播放器最多领先已显示帧 6 帧，交换 front 后才能复用旧槽，不按文件大小分配内存。媒体文件复用已有 3840 字节工作区；无 SD 诊断另有一个固定工作区。

有音轨时先预填至少 1024 个采样或读到 EOF，呈现第 0 帧后启动音频。以音频 FIFO 的 `PLAYED` 计数为时钟，目标帧为 `floor(played*fps/rate)`；无音轨时使用 1 ms RTOS tick。等待空间时让出 CPU。每次选择最新完整且到期的帧，落后的中间帧计入 dropped；读取太慢时保持当前 front 并呈现最新可用帧，避免帧环长期占满。正常结束检查 `displayed+dropped=frames`，音频保留最后采样的完整周期再停止。音频欠载或输出错误会结束播放，不能通过重置时间线隐藏丢帧。

锁顺序为 storage→graphics→audio。图形锁在整段播放期间持有，禁止另一个 TTY 覆写帧环；音频锁同样持有。UART、键盘输入任务和调度仍运行。取消、读失败或输出错误统一停音、放弃未提交帧、关闭文件并释放锁。取消保留最后已提交的 front，使用 `gfx off` 可退出图形模式；读卡取消、拔卡和使 SD 丢失初始化状态的错误会清除挂载，与前一阶段规则一致。

## VGA 格式扩展

`0x4000e000` 的原控制/状态寄存器保留。新增 `0x34 NEXT_FORMAT` 与 `0x38 ACTIVE_FORMAT`：0=RGB565、1=160×120 黑白位图的 4 倍显示。格式只接受完整 32 位写入，并与 base、stride、enable 一起提交，在垂直消隐期原子切换。读取原 `0x30 FORMAT` 仍返回 `0x565`，表示彩色路径支持。RGB565 绘图接口每次呈现显式设置格式 0。

`gfx info` 的 `RGB565 stride=1280` 前缀沿用原彩色路径说明，不表示当前活动格式或 stride；活动配置应读取 `ACTIVE_FORMAT` 与原活动 stride 寄存器。`video info` 提供播放器状态。

黑白扫描沿用四个带 epoch/行号的跨时钟行槽。每输出行读取对应源行的两个 128 位 beat，像素域按 x/4、y/4 选择位；一帧 DDR 扫描为 15360 字节，60 Hz 约 0.922 MB/s。格式通过现有 held-payload frame mailbox 传递，没有直接采样另一个时钟域的格式寄存器。欠载、AXI 错误、4 KiB 拆分、front 交换窗口和复位恢复沿用原机制。

## 素材与验收边界

用户提供的原视频已移动至 `D:\Github\DDCA_project\build\ptrocos_video\assets\badapple.mp4`，原始 SHA-256 为 `d8339642fd3303a0c4971e1564515e82f69ef61b700ce17b681debb19404c23a`。转换结果为 3481 帧、15 fps、16 kHz，长度 15780564 字节，SHA-256 为 `f0cb29a958f02063c71174b9b520f0bc59aa4c07b68ac5d65a82ad0adc02eea9`。全片 66835200 个源像素与 3713066 个 PCM 采样已和独立解包参考核对。原视频与生成文件均保存在 ignored 本地构建目录。

主仓库的 `build/ptrocos_video/BADAPPLE.PTV` 可复制到 FAT SD 卡根目录。另有 `BADAPPLE-SD.img`，为 32 MiB FAT16 文件镜像，包含 `BADAPPLE.PTV` 与 `README.TXT`。真实 FatFs、diskio 和 SD 驱动通过主机 SPI 模型读取整个视频文件，核对了 15780564 字节的 SHA-256，累计 30945 次扇区读取。镜像仅写入本地文件，未写物理卡。镜像生成与核验入口如下：

```powershell
python sw/tools/make_ptrocos_video_card.py build/ptrocos_video/BADAPPLE.PTV build/ptrocos_video/BADAPPLE-SD.img
python sw/tools/check_video_card.py build/ptrocos_video/BADAPPLE-SD.img
python sw/tools/check_video_asset_player.py build/ptrocos_video/BADAPPLE.PTV
```

真实 C 解码器和播放器也已跑完这个文件：3481 帧全部显示，丢帧为 0，66835200 个像素与 3713066 个 PCM 采样一致，模拟播放时间为 232067 ms，最大帧延迟为 16 ms。该测试使用主机图形与音频适配模型，覆盖长片帧环复用和音频采样时钟；它没有验证板卡、真实 DDR 时序或模拟音频。

2026-10-06 的板卡 UART 验收通过 9 项。三次 4 帧诊断均为 267 ms、零丢帧，最大帧延迟分别为 17/18/17 ms；每次音频播放 2133 个采样，无欠载，DDR DMA 校验通过。取消清空音频、重试、RGB565/黑白格式双向切换、回到文本模式及旧音频诊断均通过，输入丢弃计数为 0。记录位于 `build/ptrocos_video_hardware/result.json` 和 `uart.log`。

板卡已通过 JTAG 加载视频固件，写入仅限易失配置。键盘实物验收按用户要求延期；VGA 显示器未连接，SD 再次报告 `no-card`，J8 模拟波形和音质未验。主机转换、引脚模型仿真和 UART 状态不能代替 Bad Apple 的实卡、画面与音质验收。

## 实现验收

| 检查 | 已通过结果 |
| --- | --- |
| 独立 PTV 解码 | 4983 项，432 帧，252172 个 PCM 采样 |
| 独立播放器 | 69 项，1642 帧，903952 个 PCM 采样，覆盖慢读丢帧、帧环边界、取消与 tick 回绕 |
| 真实文件命令链 | 104 项，SD 驱动 132 项，覆盖 FAT12/16/32、MBR、碎片文件、取消、拔卡和 CRC 恢复 |
| FFmpeg 转换工具 | 10 项，含有声、无声、宽高比、11025 Hz 与拒绝覆盖 |
| BMP/WAV 回归 | 解码 4444 项，命令 108 项 |
| RGB565 单元仿真 | 小场景 5375 像素，全屏 1228800 像素 |
| 黑白单元仿真 | 5529599 像素，含换格式、复位、故障注入和并发访问 |
| 完整 SoC，PC style 0 | 106665218 周期，17510400 像素，4307 个 PCM 采样，197 次 SD 读取，22 次帧交换 |
| 完整 SoC，PC style 1 | 103331930 周期，16896000 像素，4307 个 PCM 采样，195 次 SD 读取，22 次帧交换 |
| 100 MHz 实现时序 | setup +0.102 ns、hold +0.018 ns、pulse +0.206 ns；负裕量总和均为 0，内部未约束端点为 0 |
| DRC | 0 Error、0 Critical Warning、50 Warning，原始报告保留 |

完整 SoC 使用真实 RV32IM/FreeRTOS 固件、碎片 FAT16 文件、延迟 MISO 的 SD 引脚模型和完整地址标记的稀疏 DDR 模型。每个已扫描像素和播放采样逐项比较，禁止覆盖正在扫描的 front；正常有声、无声、读卡取消、未挂载保护、重新挂载重试、并发 DMA、调度和返回文本均通过。style 0 另验证 CRC 错误后的挂载恢复。正常播放的图形和音频欠载、读错误均为 0；单元测试中的非零故障计数来自主动注入。两种实现最后分别记录 1064/1031 次 timer IRQ 与 2123/2070 次 yield，输入丢弃均为 0。

验收清单记录 137 个产物与 186 份源码/输入生成器的 SHA-256。产物包含原素材、转换片、FAT16 文件镜像、固件、最终位流/checkpoint、参考像素、原始报告与串口日志；失败的物理优化尝试作为追踪记录保留，不计入通过结果。提交后按清单复制到主仓库，并保存 `build/ptrocos-stage10-snapshot/`，其中 `source_snapshot/` 保留隔离工作树的实际源码字节，避免 Windows 换行转换影响追溯。

初版范围校验把动态高度放在 stride 乘法中，造成组合 DSP 路径过长。最终 RTL 分别计算 RGB565 与黑白模式的常量高度范围再选择结果。后续仅对物理布局、布线和时钟偏移做优化；临时 setup uncertainty 在最终报告前恢复为 0.000 ns，CPU RTL、100 MHz 时钟和 +0.100 ns 验收门槛均未修改。`build/ptrocos_video/recover_route8.tcl` 保存最后一次优化步骤；最终 checkpoint 使用公共 `scripts/resume_ptrocos_route.tcl -tclargs video verify` 复核通过。

CDC 报告仍包含 held-payload mailbox 与 MIG 的结构提示。与第 9 阶段相比，frame mailbox 的返回值从 enable 一位扩展为 enable/format 两位，因此一个 CDC-1 分类改为一个 CDC-4；报告路径是 `response_data_reg[1:0]` 到 `source_rdata_reg[1:0]`。两位沿用原握手，在 completion 同步后接收，并由公共验收脚本逐路径核对 10 ns datapath bound。6 个 graphics mailbox 的 12 组覆盖共 309 个端点，比第 9 阶段多一个；其余 CDC 分类数量未变。CDC 原始报告不计作零告警。
