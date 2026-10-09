# 自定义视频与 Bad Apple

主机将素材转换成 PTV1：160×120 黑白位图与单声道 PCM 交错存储，VGA 放大四倍到 640×480。构建与下载见 [开发说明](ptrocos-development.md)。

## 使用

```powershell
python sw/tools/convert_ptrocos_video.py <本地原视频> BADAPPLE.PTV --fps 15 --audio-rate 16000
```

将 PTV 文件放到支持的 FAT/exFAT SD 卡后，使用 `mount` 与 `play /BADAPPLE.PTV`。播放结束后自动返回文本 shell；Ctrl+C 取消播放、清空音频 FIFO 并返回文本 shell。`video info` 报告最近一次播放的读入、显示、丢帧、播放时间、最大延迟与音频采样率；`video test` 生成 4 帧、15 fps、8000 Hz 的诊断片段，无需 SD 卡。原 `video` 无参数命令仍显示文本控制器状态。`gfx off` 可手动返回文本模式。

转换器支持 10～30 fps，音频采样率 8000～16000 Hz，最大一小时。原始视频由 FFmpeg 解码、调整帧率、保持宽高比缩放并填黑；阈值默认 128。音频混合为单声道无符号 16 位小端 PCM，长度按视频时间截断或补中点静音。`--silent` 生成无音轨视频。转换使用磁盘临时文件和固定帧缓冲，不将整个视频装入 RAM；源文件在处理前后核对 SHA-256。已有输出默认拒绝覆盖，明确指定 `--force` 才原子替换。FFmpeg 和 NumPy 是主机转换/验证工具所需依赖，固件不需要它们。

## PTV1 格式

固定 32 字节小端文件头，无索引表。检查所有字段，拒绝大于 `UINT32_MAX` 的文件；文件长度必须与声明完全一致，截断或尾部额外数据均拒绝。

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

锁顺序为 storage→graphics→audio。图形锁在整段播放期间持有，禁止另一个 TTY 覆写帧环；音频锁同样持有。UART、键盘输入任务和调度仍运行。正常结束、取消、读失败或输出错误都经统一出口恢复文本显示：先等待已提交的换帧完成，再提交关闭图形扫描，等待提交完成后释放图形锁，保留文本缓冲中的 shell 内容。取消或错误同时停音、放弃未提交帧并关闭文件；恢复文本显示失败时，正常播放也会报告输出错误。读卡取消、拔卡和使 SD 丢失初始化状态的错误会清除挂载，与前一阶段规则一致。

## VGA 格式扩展

[图形寄存器](ptrocos-graphics.md#寄存器)的 NEXT_FORMAT/ACTIVE_FORMAT：0=RGB565，1=160×120 黑白四倍显示。格式与 base/stride/enable 在垂直消隐原子切换；RGB565 绘图显式提交格式 0。

`gfx info` 的 `RGB565 stride=1280` 前缀沿用原彩色路径说明，不表示当前活动格式或 stride；活动配置应读取 `ACTIVE_FORMAT` 与原活动 stride 寄存器。`video info` 提供播放器状态。

黑白扫描沿用四个带 epoch/行号的跨时钟行槽。每输出行读取对应源行的两个 128 位 beat，像素域按 x/4、y/4 选择位；一帧 DDR 扫描为 15360 字节，60 Hz 约 0.922 MB/s。格式通过现有 held-payload frame mailbox 传递，没有直接采样另一个时钟域的格式寄存器。欠载、AXI 错误、4 KiB 拆分、front 交换窗口和复位恢复沿用原机制。

本地原片、转换片和镜像分别为 `build/ptrocos_video/assets/badapple.mp4`、`build/ptrocos_video/BADAPPLE.PTV`、`BADAPPLE-SD.img`，均受 Git 忽略；镜像未写物理卡。复现入口见 [仿真验证](../src/sim/README.md#ptrocos)，已验证范围与物理待验项见 [开发说明](ptrocos-development.md#验证边界)。
