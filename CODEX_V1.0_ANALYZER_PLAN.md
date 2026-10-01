# CODEX_V1.0_ANALYZER_PLAN.md

```markdown
# RV32 Digital Analyzer v1.0
## Nexys A7-100T Productization Plan

## 0. 总目标

当前仓库已经完成：

- RV32 五级流水 CPU
- forwarding
- load-use hazard
- branch flush
- CRC16.B 自定义指令
- MMIO
- PWM
- Capture
- UART TX
- Performance Counter
- XSim SoC 闭环
- CPU differential verification
- Vivado implementation
- Bitstream
- JA1 -> JB1 实物 loopback

下一阶段目标：

把当前课程 MVP 升级为：

> 一个无需 PC 即可操作的 FPGA 数字信号分析仪。

最终系统：

```
                 Nexys A7-100T

              RV32 Five Stage CPU
                     |
                  MMIO Bus
                     |
     +---------------+----------------+
     |               |                |
  Capture       Generator          UI
     |               |                |
 JB[7:0]          JA[7:0]        LED/SEG/Button
     |
 Capture RAM
     |
 CPU Analysis
     |
 Frequency
 Duty Cycle
 Period
 Statistics
     |
 UART / VGA
```


==================================================
# 1. 总原则
==================================================

所有新增功能必须：

1. 保持已有 CPU 架构不变。
2. 保持 RV32 ISA 不变。
3. 保持已有 MMIO 地址兼容。
4. 每增加一个外设：
   - RTL unit test
   - SoC simulation
   - Vivado implementation
   - timing check

必须全部通过。

禁止：

- 为了功能增加修改 CPU pipeline。
- 引入 AXI。
- 引入 Linux。
- 引入 RTOS。
- 引入 DDR2（v1.0 前）。
- 引入复杂 GUI。
- 为了展示增加无关传感器。


==================================================
# 2. 当前版本冻结
==================================================

创建：

```
git tag v0.1-hardware-pass
```

更新：

STATUS.md

记录：

- CPU differential PASS
- FPGA bitstream PASS
- JA1 -> JB1 physical loopback PASS
- UART PASS
- Timing:
    setup WNS
    hold WNS
- Board:
    Nexys A7-100T


==================================================
# 3. v0.2 User Interface
==================================================

目标：

让设备脱离 PC 也可以工作。


--------------------------------------------------
3.1 Button 输入系统
--------------------------------------------------

新增：

```
src/rtl/peripheral/
    button_debounce.v
    input_sync.v
```


功能：

所有机械输入：

```
Button
 |
2FF synchronizer
 |
debounce
 |
edge pulse
 |
CPU MMIO
```


支持：

CENTER:
    start capture

LEFT:
    previous page

RIGHT:
    next page

UP:
    increase parameter

DOWN:
    decrease parameter


新增 MMIO:

Base:

```
0x40007000
```


Registers:

```
0x00 BUTTON_STATE
0x04 BUTTON_EVENT
0x08 SWITCH_STATE
```


--------------------------------------------------
3.2 Seven Segment Display
--------------------------------------------------

新增：

```
src/rtl/peripheral/sevenseg.v
```


要求：

硬件扫描：

100MHz
 |
divider
 |
8 digit refresh


CPU 不负责刷新。


新增：

```
0x40008000
```


Registers:

```
0x00 DISPLAY_DATA0
0x04 DISPLAY_DATA1
0x08 DISPLAY_DP
0x0C DISPLAY_CTRL
```


支持：

0-9

A-F

-

blank


显示页面：

Page0:

```
F 100000
```

频率 Hz


Page1:

```
d 030.0
```

占空比


Page2:

```
P 001000
```

period samples


Page3:

```
H 000300
```

high samples


Page4:

```
C 004096
```

capture count


Page5:

```
S 000123
```

CPU stall


--------------------------------------------------
3.3 LED Status
--------------------------------------------------

修改 GPIO 映射。


LED:

```
LED0-7:
    capture input state

LED8:
    armed

LED9:
    triggered

LED10:
    capture done

LED11:
    UART activity

LED12:
    generator enable

LED13:
    analyzer mode

LED14:
    PASS

LED15:
    ERROR
```


==================================================
# 4. v0.3 Real Analyzer Mode
==================================================

当前：

PWM loopback demo


升级：

支持外部输入。


目标：

JB[7:0]

直接作为：

8 channel logic analyzer


--------------------------------------------------
4.1 Capture 完善
--------------------------------------------------


保持：

4096 samples


新增：

Sample Divider


寄存器：

Capture:

```
0x40004000
```


增加：

```
0x1C SAMPLE_DIV
```


支持：

```
DIV=1

100 MHz


DIV=2

50 MHz


DIV=4

25 MHz


DIV=10

10 MHz


DIV=100

1 MHz


DIV=1000

100 kHz
```


采样周期由硬件控制。


--------------------------------------------------
4.2 多周期测量算法
--------------------------------------------------

禁止只统计一个周期。


CPU firmware:

寻找：

```
rise0
fall0
rise1
fall1
rise2
fall2
```


计算：

```
period_avg

high_avg
```


输出：

```
frequency

duty

period
```


容忍：

±1 sample


==================================================
# 5. v0.4 Edge Meter
==================================================

新增：

```
src/rtl/peripheral/
    edge_meter.v
```


目的：

精确测量低频。


硬件：

100MHz counter


输入：

JB channel


记录：

```
rise timestamp

fall timestamp
```


输出：

```
period_ticks

high_ticks
```


MMIO:

```
0x40009000
```


Registers:

```
0x00 STATUS

0x04 PERIOD

0x08 HIGH

0x0C FREQUENCY
```


最终系统：

```
Capture:
    看波形

Edge Meter:
    测参数
```


==================================================
# 6. v0.5 Digital Pattern Generator
==================================================

充分利用 JA。


新增：

```
src/rtl/peripheral/
    pattern_generator.v
```


目标：

JA[7:0]


支持：


CH0:

PWM


CH1:

clock divider


CH2:

toggle


CH3-7:

constant output


MMIO:

```
0x4000A000
```


Registers:

```
ENABLE

MODE

PERIOD

HIGH

DATA
```


最终：

```
JA[7:0]
    |
 physical cable
    |
JB[7:0]

self test
```


支持：

8 channel loopback。


==================================================
# 7. v0.6 UART RX + PC Control
==================================================


新增：

```
uart_rx.v
```


UART:

115200 8N1


扩展：

```
0x40001000
```


Registers:

```
0x00 TXDATA

0x04 STATUS

bit0 TX_READY
bit1 RX_VALID

0x08 RXDATA
```


实现：

PC command:


```
status

arm

rate 10m

channel 3

edge rising

dump

measure
```


Python:

新增：

```
tools/
    analyzer_cli.py
```


功能：

- COM连接
- 配置
- 读取结果
- 保存 CSV


==================================================
# 8. v0.7 VCD Export
==================================================


Python:

```
capture_dump.py
```


支持：

FPGA UART dump


生成：

```
capture.vcd
```


可以：

GTKWave 查看。


流程：

```
FPGA
 |
UART
 |
Python
 |
VCD
 |
GTKWave
```


==================================================
# 9. v0.8 Pre-trigger Logic Analyzer
==================================================


升级 Capture。


当前：

trigger 后采样。


升级：

ring buffer。


结构：

```
          trigger

----previous----|----after----
```


参数：

```
2048 pre

2048 post
```


实现：

```
capture_mem

write_ptr

trigger_ptr
```


状态：

```
trigger_index
```


==================================================
# 10. v0.9 VGA Waveform Viewer
==================================================


使用 Nexys A7 VGA。


目标：

无需 PC 显示波形。


显示：

```
+--------------------------------+

CH0 ----____----____----

CH1 __----____----_____

CH2 -------------------

        ^
      trigger


Freq:
100kHz

Duty:
30%

Rate:
100M

+--------------------------------+
```


实现：

```
capture RAM

    |

VGA renderer

    |

RGB output
```


不要 framebuffer。


直接读取 waveform。


==================================================
# 11. 最终 v1.0 Definition of Done
==================================================


## CPU

[x] 五级流水

[x] forwarding

[x] hazard

[x] branch flush

[x] CRC16.B

[x] differential verification


## Analyzer

[x] 8 channel input

[x] adjustable sample rate

[x] trigger

[x] capture RAM

[x] frequency measurement

[x] duty measurement

[x] edge meter


## Generator

[x] PWM

[x] multi-channel digital output


## UI

[x] buttons

[x] switches

[x] LEDs

[x] RGB LEDs(optional)

[x] seven segment


## Communication

[x] UART TX

[x] UART RX

[x] PC CLI


## Visualization

[x] VCD export

[x] VGA waveform


## Hardware

[x] Bitstream

[x] Timing PASS

[x] Nexys A7 physical validation


==================================================
# 12. 每阶段验收
==================================================


每个 milestone:

必须：

1.
make test

2.
XSim

3.
Vivado synth

4.
Vivado implementation

5.
Timing:

WNS >=0


6.
更新 STATUS.md


禁止：

"代码完成但是没有验证"



==================================================
# 13. 最终展示脚本
==================================================


现场：

1.

打开板子


2.

数码管显示：

```
READY
```


3.

JA 输出测试波形


4.

JB 输入


5.

按 CENTER


6.

数码管显示：

```
F100000
d030.0
```


7.

LED 显示：

```
capture done
```


8.

UART 输出：

```
RV32 ANALYZER

RATE=100M

FREQ=100000Hz

DUTY=30%

RESULT=PASS
```


9.

VGA 显示波形。


最终效果：

一台由自研 RV32 CPU 驱动的 FPGA 数字逻辑分析仪。


END
```