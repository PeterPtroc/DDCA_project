# 课设仿真演示：数组求和与 CRC 校验

本演示实例化实际的 `rv32im_core`，使用指令 ROM、同步数据 RAM 和自动断言，不需要板卡、MIG 或操作系统。默认程序完成数组求和，补充程序用自定义 `crc16.b` 指令完成数据块校验。

**流水级数需要如实说明：课件要求五级，而当前 CPU 的 MEM 因同步存储器拆成 MEM1、MEM2，实际是 IF → ID → EX → MEM1 → MEM2 → WB 六级。** 波形按五类功能分组并不能消除这一差异。本次仅调整演示程序和观察信号，没有修改 CPU 的流水结构。仿真工具为 Vivado XSim，课件列出的仿真环境为 ModelSim。

## 课设要求与展示内容

| 课设内容 | 展示内容 | 对应代码或信号 |
| --- | --- | --- |
| 指令执行与流水线重叠 | 多条指令同时处在不同阶段，同一条指令逐拍推进 | IF、ID、EX、MEM、WB 的 `*_text`、valid 和 PC |
| 数据信息流与控制信息流 | 译码产生控制，随流水寄存器传递，最终决定访存或写回 | ID 的 `dec_*`，EX 的 `idex_*`，MEM 的 `exmem_*` / `mem2_*`，WB 的写回信号 |
| forwarding | 递减计数器后立即用其结果判断循环分支 | I06 → I07；EX 的操作数、`fwd_a/fwd_b` |
| Load-use 冒险 | `lw` 后立即使用加载结果，前端保持、EX 插入气泡 | I03 → I04；`stalled`、PC、各级 valid |
| B 型扩展 `bne` | 剩余元素数不为零时回到循环头，最后一次不跳转 | I07，目标 PC=`0x0c` |
| 分支冲刷 | 循环未结束时，提前取到的结果存储和完成指令被冲刷 | I08、I09；`flushed`，只允许最后写结果一次 |
| 定制 RISC-V 指令 | 对数据块逐字节计算 CRC-16/MODBUS | `crc_demo.S`、`crc16.b`、CRC 波形组 |
| 基础九条指令及移位、`blt/bge/auipc` 等扩展 | 另用定向测试和参考模型逐条对比，两个短程序不覆盖全部指令 | `sw/firmware/isa_test.S`、`hazard_test.S`、`crc_test.S`；`scripts/test_rv32m.ps1` |

课件第 6 页的九条基础指令为 `add/slt/sltu/ori/lui/lw/sw/beq/jal`。不能仅凭数组求和通过，就声称这些指令全部通过；指令覆盖由补充定向测试提供证据。

## 主演示：数组求和

程序从数据 RAM 读取五个整数 `1、2、3、4、5`，累加后把结果 `15` 写到数组后面的一个字。汇编源文件为 [array_sum.S](../src/sim/pipeline/array_sum.S)，测试平台内置相同机器码，不需要额外构建固件。

```c
int sum = 0;
for (int i = 0; i < 5; ++i)
    sum += data[i];
result = sum;   // 15，写入数据 RAM 的字节地址 20
```

| 标签 / PC | 指令 | 实际功能 |
| --- | --- | --- |
| I00 / `0x00` | `addi x1,x0,0` | 输入数组的起始字节地址为 0 |
| I01 / `0x04` | `addi x2,x0,5` | 待处理元素数为 5 |
| I02 / `0x08` | `addi x3,x0,0` | 累加和清零 |
| I03 / `0x0c` | `lw x4,0(x1)` | 读一个元素 |
| I04 / `0x10` | `add x3,x3,x4` | 累加这个元素 |
| I05 / `0x14` | `addi x1,x1,4` | 指针移到下一个整数 |
| I06 / `0x18` | `addi x2,x2,-1` | 剩余元素数减一 |
| I07 / `0x1c` | `bne x2,x0,-16` | 未结束则跳回读取指令 |
| I08 / `0x20` | `sw x3,20(x0)` | 把结果写回数据 RAM |
| I09 / `0x24` | `addi x5,x0,1` | 标记完成，测试平台检查结果并结束 |

这里 I07 是循环条件，取决于实际计数器。前四次跳转，第五次不跳转。前四次提前取到的 I08、I09 必须被冲刷，不能提前存储结果或结束程序。

| 完成的元素 | 当前输入 | 累加和 x3 | 指针 x1 | 剩余数 x2 |
| --- | --- | --- | --- | --- |
| 第 1 个 | 1 | 1 | 4 | 4 |
| 第 2 个 | 2 | 3 | 8 | 3 |
| 第 3 个 | 3 | 6 | 12 | 2 |
| 第 4 个 | 4 | 10 | 16 | 1 |
| 第 5 个 | 5 | 15 | 20 | 0 |

默认预期：53 个记录周期、30 条指令提交、10 拍加载后使用停顿、4 次冲刷、5 次输入读取、1 次结果写入。一次加载后使用停顿两拍，五次循环合计十拍。

测试平台逐条检查退休 PC、加载数据、每轮累加值、指针和计数器更新，且禁止提前或重复写结果。可选 `ALT_DATA` 输入为 `10、-4、0、12、-2`，结果为 16，用于验证程序确实读取并处理输入。

## 补充演示：自定义 CRC 指令

[crc_demo.S](../src/sim/pipeline/crc_demo.S) 对字符串 `123456789` 计算 CRC-16/MODBUS。保留同一循环结构，将累加替换成 `crc16.b x3,x3,x4`；输入为九个字符，CRC 初值低十六位为 `0xffff`，最终将 `0x4b37` 写入数据 RAM 字节地址 36。

这个例子可说明定制指令的用途：一条 `crc16.b` 对一个字节完成 CRC 更新，替代软件逐位移位与条件异或。CPU 的自定义译码选择 CRC 运算结果，再沿正常流水线写回寄存器。该演示验证了功能，不能据此声称已测得相对软件实现的加速比。

预期：89 个记录周期、50 条指令提交、18 拍停顿、8 次冲刷、9 次 CRC 指令提交、1 次结果写入。CRC 组以十六进制显示累计值和最终输出。

## 启动与切换

优先使用仓库根目录的 `open_vivado_gui.bat` 打开 PtrocOS 主工程。工程已登记两个仿真集：

- `sim_pipeline`：数组求和，默认激活。
- `sim_pipeline_crc`：CRC 校验，已配置 `CRC_DEMO` 参数。

在 **Simulation Sources** 中选择需要的仿真集并 **Set as Active**，再点击 **Run Simulation → Run Behavioral Simulation**。波形分组会随仿真加载，程序运行至断言检查结束，保留实时会话供 `restart` 和逐拍观察。硬件综合顶层仍为原板级顶层。

关键指令标签、累计结果、停顿、冲刷和前递选择直接显示在波形顶部，不必展开分组。启动入口在完成后重载显示配置，将时间范围设置到有效运行区间，并将游标放到完成时刻。详细阶段和控制信号仍在下方分组中。

若使用旧配置时只看见分组标题，点击组名前的三角形展开，再点 **Zoom Fit**。若完成后误执行了 `run all` 导致时间轴持续推进，先点 **Cancel** 停止运行，再执行 `source -encoding utf-8 src/sim/pipeline/start_simulation.tcl` 重新载入显示。本例时钟在 `done=1` 后停止产生事件，新编译的版本再次 `run all` 会自行返回；要重新执行程序须先 `restart`。

已经打开的旧工程可在关闭当前仿真后，直接在 Tcl Console 登记一次，无需重新创建工程：

```tcl
source -encoding utf-8 C:/Users/zhanghengyi/Desktop/DDCA_project/src/sim/pipeline/add_to_project.tcl
```

也可用 Tcl 选择并启动其中一个仿真集：

```tcl
current_fileset -simset sim_pipeline
launch_simulation
```

切换前先手动关闭当前仿真，再选择另一个仿真集：

```tcl
close_sim
current_fileset -simset sim_pipeline_crc
launch_simulation
```

两个仿真集使用独立的 CPU 源列表，不编译板级 MIG，不改变主工程的设计源、约束或固件参数。`src/sim/pipeline/` 只是源文件分组目录，仿真已经属于同一个主工程。汇编与波形脚本也登记在工程的 Utility Sources 中。

仅需要脱离主工程演示时，仍可在未加载工程的 Vivado 窗口执行原入口：

```tcl
cd C:/Users/zhanghengyi/Desktop/DDCA_project
source scripts/create_pipeline_demo.tcl
```

此兼容入口使用 `build/pipeline_demo/pipeline_demo.xpr` 的 `sim_1`，保留手动加载波形与交互仿真方式。不同输入测试的 XSim 参数为 `-testplusarg ALT_DATA`。

## 现场观察顺序

1. 展开 Results，说明 `pointer` 是字节地址，`remaining` 是剩余数，`accumulator` 是累计结果，`current_value` 是当前输入，`output_value` 是实际 RAM 输出。
2. 展开阶段标签，沿 I00 观察 45 ns 进入 ID、55 ns 进入 EX、65 ns 进入 MEM1、75 ns 进入 MEM2、85 ns 进入 WB。后面的停顿和循环会改变其他指令的推进时刻，不能沿用旧短程序的 90 ns 六条有效指令示例。
3. 放大第一轮 I03、I04：加载后立即使用时，IF/ID 保持两拍、EX 出现气泡，加载继续向后推进，数据就绪后从 WB 前递给加法。
4. 放大 I06、I07：计数器递减结果通过前递用于分支比较。前四次分支跳转，I08、I09 被冲刷；最后一次计数器为零，退出循环。
5. 对照课件控制图，比较 `lw` 和 `sw` 的 `dec_mem_re/dec_mem_we/dec_reg_we/dec_wb_mem`，再沿 EX、MEM、WB 查看控制信号传递。控制信号仅在对应阶段 valid 有效时有意义。
6. 最后展示 RAM 输出 15、`PIPELINE DEMO PASS` 和 `FUNCTION DEMO PASS`。切换 CRC 后展示输出 `0x4b37` 和 `crc_count=9`。

`BUBBLE` 表示 valid=0，不代表其余 PC 和数据一定清零。主工程中的周期记录位于 `build/vivado/ptrocos.sim/<仿真集名>/behav/xsim/pipeline_cycles.csv`；独立兼容工程中的记录位于 `build/pipeline_demo/pipeline_demo.sim/sim_1/behav/xsim/pipeline_cycles.csv`。CSV 在上升沿状态更新前采样，波形在该沿之后显示更新后的状态。逐拍操作仍可使用 `restart`、`run 40 ns`，随后每次 `run 10 ns`。

## 文件与验证边界

| 文件 | 用途 |
| --- | --- |
| `src/sim/pipeline/array_sum.S` | 默认数组求和程序，中文注释 |
| `src/sim/pipeline/crc_demo.S` | 自定义 CRC 功能程序，中文注释 |
| `src/sim/pipeline/tb_pipeline_demo.sv` | 两个程序的内置机器码、数据 RAM、逐周期记录与断言 |
| `src/sim/pipeline/waves.tcl` | 功能结果、阶段、控制信号、冒险和 CRC 波形 |
| `src/sim/pipeline/add_to_project.tcl` | 将两个仿真集登记到当前主工程 |
| `src/sim/pipeline/start_simulation.tcl` | 仿真启动时加载波形、运行程序，保留交互会话 |
| `scripts/create_pipeline_demo.tcl` | 独立兼容工程的交互仿真入口 |

这两个短程序用于解释功能和流水线机制，不覆盖整个 SoC、可变延迟总线或全部指令。完整指令验证使用已有回归；上板验收、实现时序以及严格五级流水结构的符合性需要分别说明。

本次实际运行的补充验证使用同一个 `rv32im_core`，将现有 `tb_cpu_trace` 的 CPU 实例替换为该核，临时测试平台和日志保存在 `build/course-demo-test/`。结果为：ISA 定向程序 117 条提交、冒险程序 47 条提交、CRC 程序 26 条提交，均与 `rv32_ref.py` 的参考提交轨迹逐条一致。该记录证明已运行的用例，不表示执行了完整系统回归。
