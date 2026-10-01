# 最终演示脚本

演示前：烧录最终 bitstream，关闭 SW13，除说明项外先把开关置 0；准备 JA1→JB1 跳线和已安装 pyserial 的 PC。

1. 上电并释放 RESET，指出数码管 READY。
2. 断电接好 JA1→JB1，再上电；设置 SW3=1、频率 preset 9、duty preset 4，得到 100 kHz/30%。
3. 展示 RGB0 绿色 RUN、RGB1 绿色 signal，以及 LED[15:0] 的稳定数字波形。
4. LEFT/RIGHT 展示频率、占空比、周期、高电平、低电平：约 100 kHz、30.00%、10.00 us、3.00 us、7.00 us。
5. UP/DOWN 改时基，指出数码管约 1 秒的时基提示和 LED 脉宽变化。
6. 切换 SW0 rising/falling，展示中央触发边沿方向变化。
7. CENTER 进入 HOLD：RGB0 蓝，LED 和数值都冻结；再按一次恢复 RUN。
8. 将 SW[2:1] 置 SINGLE，按 CENTER；RGB0 黄，live 与 4096 点 deep capture 完成后变蓝并冻结。
9. 切 NORMAL 后关闭发生器，说明没有匹配触发时保留最后一帧；切 AUTO 后恒定电平仍会超时刷新。
10. 拔掉跳线或保持发生器关闭，等待无信号 timeout：RGB1 红、数码管 `no-SiG`，旧频率不再显示。恢复跳线与发生器。
11. 打开 SW14 自检，100 kHz/30% 应为 RGB1 绿；执行 `status`，展示 `SELFTEST PASS`。改变不匹配条件时展示 FAIL，然后恢复。
12. PC 执行：

    ```powershell
    python tools/analyzer_cli.py --port COM9 measure
    python tools/analyzer_cli.py --port COM9 dump --output demo.csv --vcd demo.vcd --packet demo.cap2
    python tools/analyzer_cli.py --port COM9 perf
    ```

    说明 dump 是 4096 bit→512 byte，CLI 已验证 CRC16，VCD 时间步来自包头。
13. 打开 SW15，用 LEFT/RIGHT 展示 cycle、instret、stall、EX/WB forwarding、flush、branch/taken 与 CRC 计数器。说明五级流水 CPU 是控制面，专用 RTL 是实时数据面；`CRC16.B` 已在产品传输中真实使用。
