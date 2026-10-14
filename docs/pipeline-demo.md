# 在 Vivado 中观察流水线

本演示直接实例化项目的 `rv32im_core`，使用内置短程序和同步数据 RAM，不需要板卡、MIG 或编译操作系统。CPU RTL 不作修改。

**时序边界：当前实现并非严格的五拍流水线。** IF / ID / EX / MEM / WB 是五类功能，MEM 为同步存储器细分成 MEM1、MEM2，实际指令按 IF → ID → EX → MEM1 → MEM2 → WB 推进，每拍 10 ns。不能把 MEM2 隐藏后认为指令五拍完成。

## 启动

打开一个没有加载工程的 Vivado 窗口，在底部 Tcl Console 输入（路径按实际位置调整）：

```tcl
cd C:/Users/13050154790/Desktop/DDCA_project
source scripts/create_pipeline_demo.tcl
```

脚本创建或复用 `build/pipeline_demo/pipeline_demo.xpr`，启动行为仿真，添加波形并运行至检查结束。以后也可打开此工程，选择 **Run Simulation → Run Behavioral Simulation**，在 Tcl Console 执行：

```tcl
source C:/Users/13050154790/Desktop/DDCA_project/src/sim/pipeline/waves.tcl
run all
```

波形配置保存在 `build/pipeline_demo/pipeline_demo.wcfg`，可通过波形窗口打开。使用 Zoom Fit 查看全程；想逐拍观察，执行 `restart`，先 `run 40 ns` 完成复位，然后每次 `run 10 ns`。时钟周期 10 ns，40 ns 下降沿解除复位，45 ns 为第一条指令进入 ID 的上升沿。

## 观察顺序

先放大 40～100 ns，沿着 `I00` 标签观察：45 ns 进入 ID，55 ns 进入 EX，65 ns 进入 MEM1，75 ns 进入 MEM2，85 ns 进入 WB。在 90 ns 放置光标，IF 到 WB 同时分别是 I05、I04、I03、I02、I01、I00，展示六条指令重叠执行。复位后的第一段 IF 从 40 ns 到 45 ns，只有半拍。

1. 展开 IF、ID、EX、MEM、WB，优先看 ASCII 的 `*_text`。同一个 Ixx 标签每拍向后移动，多条指令同时存在就是流水线重叠。`BUBBLE` 表示 valid=0，此时其余 PC/数据可能仍保留旧值，不能当有效指令。
2. I02 计算 `x3=5+7=12`，I03 紧接着计算 `x4=12+5=17`。观察 EX 的操作数和 Hazards 的 `fwd_a/fwd_b`：0=寄存器值，1=EX/MEM，2=MEM2，3=WB。
3. I04 把 17 存入 RAM[0]，I05 读入 x5，I06 立即使用 x5 计算 22。`stalled` 连续两拍为 1，IF 的 PC 和 ID 指令保持不动，EX 注入气泡，较老的指令继续前进。
4. I07 是恒成立的 BEQ，目标 PC=0x28。分支在 EX 决定，`flushed=1` 后年轻指令变成气泡。两个 `WRONG` 标签允许出现在 IF/ID，但不应退休，错误路径的 RAM[1] 写入也不能发生。
5. I10 得到 x7=23，I11 为完成标记。WB 中 `retired`、`rpc`、`dest` 和 `result` 展示最终提交。

运行成功时控制台出现 `PIPELINE DEMO PASS`；超时、结果错误、意外 trap、错误路径退休或事件计数不符都会 `$fatal`。预期提交 10 条指令、load-use 停顿 2 拍、冲刷 1 次。

每周期记录为 `pipeline_cycles.csv`，Vivado 工程模式下位于 `build/pipeline_demo/pipeline_demo.sim/sim_1/behav/xsim/`。CSV 在上升沿寄存器更新前采样，表示该沿将推进的各级指令；波形在该沿之后显示更新后的各级状态，两者存在这一采样视角差别。

这是 CPU 流水线教学用的确定性短测试，不覆盖整个 SoC、可变延迟总线或 RV32M 多周期运算；已有系统回归仍由原测试入口负责。

## 文件组织

| 路径 | 用途 |
| --- | --- |
| `scripts/create_pipeline_demo.tcl` | Vivado 工程创建、复用和仿真入口 |
| `src/sim/pipeline/tb_pipeline_demo.sv` | 内置程序、同步 RAM、逐周期记录和结果断言 |
| `src/sim/pipeline/waves.tcl` | 阶段分组和 ASCII 指令显示 |
| `docs/pipeline-demo.md` | 启动和读图说明 |
| `build/pipeline_demo/` | 生成的工程、波形和仿真结果，不纳入版本管理 |

旧演示工程通过入口脚本重新打开时，会自动更新 testbench 路径。
