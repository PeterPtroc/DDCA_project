# 功能：对字符串“123456789”计算 CRC-16/MODBUS，并将结果保存到 RAM。
# 初始 CRC 为 0xffff，最终结果为 0x4b37；每个字符在本例 RAM 中占一个字。
# x1 为地址指针，x2 为剩余字节数，x3 为 CRC，x4 为当前字符。

    addi x1, x0, 0       # 数据块从数据地址 0 开始
    addi x2, x0, 9       # 共九个字符
    addi x3, x0, -1      # CRC 初值低十六位为 0xffff

crc_loop:
    lw   x4, 0(x1)       # 取出当前字符，使用其低八位
    crc16.b x3, x3, x4   # 自定义指令：将一个字节更新到 CRC 中
    addi x1, x1, 4       # 移到下一个字符
    addi x2, x2, -1      # 剩余字符数减一
    bne  x2, x0, crc_loop # 未处理完则继续循环

    sw   x3, 36(x0)      # 把 CRC 写到数据块后面，结果应为 0x4b37
    addi x5, x0, 1       # 完成标志
