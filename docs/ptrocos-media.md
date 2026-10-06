# BMP 显示与 WAV 播放

第 9 阶段的 `media` 固件通过 FatFs 读取 BMP/WAV：BMP 转换成 RGB565 后在垂直消隐期交换 DDR framebuffer，WAV 转换成单声道 PCM 后送入板载音频 FIFO。原 CPU、生产 SoC、FreeRTOS 内核和原工程入口继续冻结。验证记录及文件 SHA-256 见 [ptrocos-media-validation.json](ptrocos-media-validation.json)。

## 命令与文件格式

```text
mount
bmp /IMAGE.BMP
wav /SOUND.WAV
audio info
audio test
gfx off
```

`bmp` 支持未压缩 BI_RGB、24/32 位 BGR/BGRX，DIB 长度 40～124 字节，尺寸 1～640 × 1～480。正高度从下向上排列，负高度从上向下排列；32 位文件的第四字节不参与颜色转换。图像显示在左上角，其余区域填黑，不缩放。文件按磁盘行顺序读取，再写入对应的屏幕行，避免底向上的图片反复倒寻址 FAT 链。调色板、RLE 和 BITFIELDS 格式会被拒绝。

`wav` 支持 RIFF/WAVE 的 PCM format 1，8/16 位、单声道或双声道、8000～48000 Hz。8 位输入为无符号，16 位输入为有符号小端；双声道使用 32 位和取平均，向零截断，再加 32768 送入无符号 16 位 FIFO。不重采样。解析器处理额外 chunk 和奇数字节 padding，允许 `data` 在 `fmt ` 前，拒绝重复 `fmt `/`data`、空数据、不完整采样帧、不一致的 blockAlign/byteRate、越界长度与截断文件。

两个解析器都在文件边界内检查长度，再开始输出。媒体工作区固定占 3840 字节，包含一个最大输入行和一个 RGB565 输出行；WAV 复用它，每批最多 256 帧。文件大小不会决定 RAM 分配。`media` 固件使用 `-Os`，指令与数据 BRAM 容量仍各为 64 KiB。

## 取消与资源所有权

媒体命令在已有存储命令 mutex 内执行，文件流和静态工作区不会被两个 TTY 同时使用。锁顺序为存储锁到图形锁或音频锁；普通 `gfx`、`audio test` 不获取存储锁。等待锁、绘图、文件读和音频排空都响应 Ctrl+C。

BMP 未提交前取消或读失败会放弃 back buffer，保留 front buffer。已经发出的换帧按图形模块的规则等待完成或报告 1 秒超时。WAV 取消、输出错误或读卡失败会清空 FIFO 并关闭放大器；正常结束则先排空最后一批采样。输出期间取消保留挂载，SD 事务取消、拔卡或使驱动失去初始化状态的错误会清除应用层挂载状态，需要重新 `mount`。文件关闭和锁释放均经过统一出口。

## 音频电路与寄存器

板载 J8 为单声道音频口。[Digilent 参考手册](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf)第 15 节要求 `AUD_PWM` 为开漏：逻辑 0 拉低，逻辑 1 高阻，由模拟电源上拉。实验顶层使用 `OBUFT`，其数据输入固定为 0；布线后的验收脚本检查这一连接及 A11/D12 引脚。`AUD_SD` 高电平启用放大器，其极性来自 [官方 AudioDemo](https://github.com/Digilent/Nexys-A7-100T-OOB/blob/master/src/hdl/AudioDemo.vhd)。复位、取消和播放结束时 `AUD_SD=0`、`AUD_PWM=Z`。

音频模块与 CPU 共用 100 MHz 时钟，4096 × 16 位 FIFO 使用同步读 BRAM。每个 CPU 周期累加采样率，达到 100000000 时减去该值并取下一帧，使 11025/44100 Hz 等采样率的长期频率保持精确；相邻间隔只差一个 CPU 周期。16 位 PCM 通过一阶脉冲密度调制输出，板载低通滤波器恢复模拟电压。中点 32768 对应静音；这不是 65536 周期的低频 PWM。

音频基址为 `0x4000f000`。

| 偏移 | 名称 | 含义 |
| --- | --- | --- |
| `0x00` | DATA | 写入一个无符号 16 位采样，低两个 byte strobe 必须同时有效 |
| `0x04` | RATE | 8000～48000 Hz；仅停止时接受完整 32 位写入 |
| `0x08` | CMD | bit0=开始，bit1=取消并复位队列/计数，bit2=排空结束，bit3=清 sticky 错误 |
| `0x0c` | STATUS | bit0=运行，bit1=排空，bit2=完成，bit3=配置错误，bit4=欠载，bit5=溢出 |
| `0x10` | QUEUED | 尚未播放的采样数 |
| `0x14` | CAPACITY | 4096 |
| `0x18` | PLAYED | 已取出的采样数；欠载静音不计入 |
| `0x1c` | UNDERRUNS | FIFO 为空且未请求结束时的缺失采样数 |
| `0x20` | PCM | 当前保留的输出采样 |

开始播放前通常预填 1024 帧，短文件在最后一批入队后启动。软件等待空间时每 1 ms 让出 CPU；从开始等待起 1 秒仍未取得空间或排空则报告输出错误。FIFO 满时拒绝覆盖，排空期间拒绝新写入。欠载输出中点静音并计数；媒体命令发现 sticky 错误后停止播放。正常结束保留完成计数供 `audio info` 检查，下一次播放先复位计数。

## 验证

复现入口：`scripts/test_ptrocos_media.ps1`。结果、覆盖范围与产物 SHA 见 [ptrocos-media-validation.json](ptrocos-media-validation.json)。统一构建、命令入口和物理待验项见 [开发说明](ptrocos-development.md)。
