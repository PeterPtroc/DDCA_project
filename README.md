# RV32 Real-Time Digital Scope v2.0

基于自研五级流水 RV32I 处理器的单通道实时数字示波分析仪，面向 3.3 V 数字方波、PWM、时钟和 GPIO。实时波形与边沿测量由专用 RTL 完成，CPU 负责配置、板载 UI、UART、深度采集管理和使用自定义 `CRC16.B` 指令保护采集包。

```text
       JA1 TEST OUT
            |
            | optional jumper
            v
           JB1
            |
      2FF Synchronizer
            |
    +-------+-------+
    |               |
 Edge Meter      Live Scope ----> LED[15:0]
    |               |
    +------ RV32 CPU +----> Seven Segment
            |
          UART PC
```

## 五分钟上手

1. Nexys A7-100T 断电时用一根杜邦线连接 `JA1 -> JB1`。
2. 将 `SW3=1`、`SW[7:4]=9`、`SW[11:8]=4`，即内置 100 kHz、30% 占空比信号；其余开关先置 0。
3. 在仓库根目录生成固件、验证并实现：

   ```powershell
   .\scripts\test_windows.ps1
   vivado -mode batch -source scripts/create_vivado_project.tcl
   vivado -mode batch -source scripts/build_bitstream.tcl
   vivado -mode batch -source scripts/program_analyzer.tcl
   ```

4. `LED[15:0]` 显示从 LED0（最早）到 LED15（最新）的 16 点实时波形；数码管默认显示频率，LEFT/RIGHT 切换测量页，UP/DOWN 改变时基，CENTER 切换 RUN/HOLD。
5. 自动检查串口与真实 `JA1 -> JB1` 回路：

   ```powershell
   .\scripts\test_hardware.ps1 -Port COM9
   ```

   打开 SW14 后可执行正式自检门禁；脚本还会把真实 CAP2、CSV 和 VCD
   保存到 `build/hardware/`：

   ```powershell
   .\scripts\test_hardware.ps1 -Port COM9 -RequireSelfTest
   ```

最终 bitstream 为 `build/vivado/rv32_realtime_scope.bit`，默认固件为 `build/hex/scope.hex`。

> **电气安全：** JB1 只能接 3.3 V LVCMOS 兼容数字信号。不得接 5 V、12 V、RS-232、电源轨、模拟高压或未知电平。本项目没有商业示波器的输入保护和模拟前端。

## 仪器功能

- 共享同一个 2FF 同步器的 JB1 单通道输入。
- 16 点低延迟 LED 波形；AUTO、NORMAL、SINGLE、FREE、RUN/HOLD；上升沿/下降沿触发，触发点固定在 LED7 附近。
- 10 ns 时钟分辨率；16 档 1-2-5 时基，单 LED 间隔从 10 ns 到 1 ms。
- 硬件测量频率、周期、高/低电平时间、占空比、信号丢失；可选四周期平均。
- 4096×1 深度采集，固定 2048 点预触发和 2048 点触发后窗口。
- JA1 单通道可编程发生器，16 档频率和 16 档占空比。
- 512 字节单通道位打包，CAP2 头与 CRC16/MODBUS；CRC 逐字节由 CPU 的 `CRC16.B` 指令计算。
- 115200 8N1 UART CLI，CSV 与自动时基 VCD 导出。
- SW15 架构调试页保留 cycle、instret、stall、forwarding、flush、branch、CRC 计数器。

## 板载控制

| 输入 | 作用 |
| --- | --- |
| SW0 | 0 上升沿；1 下降沿 |
| SW[2:1] | 00 AUTO；01 NORMAL；10 SINGLE；11 FREE |
| SW3 | 内置 JA1 发生器开关 |
| SW[7:4] | 发生器频率预设 |
| SW[11:8] | 发生器占空比预设 |
| SW12 | 四周期测量平均 |
| SW13 | 每 100 ms 输出一个 MEA2 遥测包 |
| SW14 | 真实 JA1→JB1 自检比较 |
| SW15 | CPU 架构调试 UI |
| CENTER | RUN/HOLD；SINGLE 模式下启动一次采集 |
| LEFT / RIGHT | 上一页 / 下一页 |
| UP / DOWN | 更快 / 更慢时基，临时显示 1 秒 |

RGB0：绿=RUN，蓝=HOLD，黄=SINGLE 等待（数码管 `Ar`），红=错误（数码管 `Err`）。RGB1：绿=有效信号，黄=等待触发，红=无信号；自检时绿/红表示 PASS/FAIL。

## PC 接口

安装 `pyserial` 后使用单通道命令：

```powershell
python -m pip install pyserial
python tools/analyzer_cli.py --port COM9 status
python tools/analyzer_cli.py --port COM9 measure
python tools/analyzer_cli.py --port COM9 run
python tools/analyzer_cli.py --port COM9 hold
python tools/analyzer_cli.py --port COM9 single
python tools/analyzer_cli.py --port COM9 perf
python tools/analyzer_cli.py --port COM9 dump --output capture.csv --vcd capture.vcd --packet capture.cap2
```

CAP2 文件自带 `sample_div`，独立转换 VCD 不需要手工填写采样率：

```powershell
python tools/capture_dump.py capture.cap2 capture.vcd
```

## 验证与文档

- [当前状态与签核](STATUS.md)
- [系统架构](docs/architecture.md)
- [用户指南](docs/user_guide.md)
- [技术规格](docs/specification.md)
- [实板验证记录](docs/hardware_validation.md)
- [最终演示脚本](docs/demo_script.md)

旧多通道版本固定在 tag `v1.0-multichannel-prototype`；v2.0 发布标签为
`v2.0-realtime-scope`。实板签核范围和用户免除项以
`docs/hardware_validation.md` 为准。
