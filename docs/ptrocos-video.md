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

## 验证

复现入口：`scripts/test_ptrocos_video.ps1`。结果、覆盖范围与产物 SHA 见 [ptrocos-video-validation.json](ptrocos-video-validation.json)。统一构建、命令入口和物理待验项见 [开发说明](ptrocos-development.md)。

用户提供的原片保存于 `build/ptrocos_video/assets/badapple.mp4`；转换片为 `build/ptrocos_video/BADAPPLE.PTV`，3481 帧、160×120、15 fps、16 kHz 单声道，15,780,564 字节。全片像素和采样已由独立主机参考核对；`BADAPPLE-SD.img` 是生成的 FAT16 镜像，未写物理卡。
