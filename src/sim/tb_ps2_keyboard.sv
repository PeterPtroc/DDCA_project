`timescale 1ns/1ps
module tb_ps2_keyboard;
  reg clk=0,rst=1,pc=1,pd=1,valid=0,we=0;
  reg [31:0] addr=0,wdata=0;
  reg [3:0] strb=15;
  wire [31:0] rdata;
  wire irq;
  integer packets=0;
  ps2_keyboard #(.TIMEOUT_CYCLES(2000)) dut(.clk(clk),.rst(rst),.ps2_clk(pc),.ps2_data(pd),
      .valid(valid),.we(we),.addr(addr),.wdata(wdata),.wstrb(strb),.rdata(rdata),.irq(irq));
  always #5 clk=~clk;
  task bit_send(input bit b);
    @(negedge clk);pd=b;repeat(50) @(negedge clk);pc=0;
    repeat(150) @(negedge clk);pc=1;repeat(150) @(negedge clk);
  endtask
  task packet_send(input byte b,input bit bad_parity=0,input bit bad_stop=0);
    bit_send(0);
    for(integer i=0;i<8;i++) bit_send(b[i]);
    bit_send((~^b)^bad_parity);bit_send(!bad_stop);
    pd=1;repeat(40) @(negedge clk);packets++;
  endtask
  task read_check(input integer offset,input [31:0] expected);
    @(negedge clk);addr=offset;valid=1;we=0;
    #1;if(rdata!==(offset==0 ? expected|32'h30 : expected)) $fatal(1,"PS2 offset %x expected=%x actual=%x",offset,expected,rdata);
    @(negedge clk);valid=0;
  endtask
  task command(input [31:0] value,input [3:0] mask=15);
    @(negedge clk);addr=24;wdata=value;strb=mask;valid=1;we=1;
    @(negedge clk);valid=0;we=0;strb=15;
  endtask
  initial begin
    repeat(10) @(negedge clk);rst=0;
    read_check(0,0);read_check(4,0);
    // 滤波器应滤除任一输入端上持续时间不足八个本地时钟周期的脉冲。
    pc=0;pd=0;repeat(2) @(negedge clk);pc=1;pd=1;repeat(30) @(negedge clk);
    read_check(0,0);
    for(integer i=0;i<256;i++) begin
      packet_send(i);if(!irq) $fatal(1,"Missing PS2 irq");
      read_check(0,32'h101);read_check(4,i);read_check(0,0);
    end
    read_check(8,256);
    read_check(28,2816);
    packet_send(8'h1c,1);packet_send(8'h32,0,1);
    bit_send(1); // 错误的起始位
    read_check(0,4);read_check(12,3);
    bit_send(0);bit_send(1);repeat(2100) @(negedge clk);
    read_check(0,12);read_check(16,1);
    packet_send(8'h5a);read_check(4,8'h5a); // 验证截断帧之后的恢复
    command(3,4'b0010);read_check(12,3); // 错误的字节使能不得触发清零
    command(3);read_check(0,0);read_check(8,0);read_check(12,0);read_check(16,0);
    for(integer i=0;i<32;i++) packet_send(i+32);
    read_check(0,32'h2001);
    packet_send(8'hff);read_check(0,32'h2003);read_check(20,1);
    for(integer i=0;i<32;i++) read_check(4,i+32);
    read_check(0,2);read_check(4,0);read_check(8,33);
    command(2);read_check(0,0);
    // 已满的 FIFO 可在软件弹出一个字节的同一时钟沿接收一个新字节。
    for(integer i=0;i<32;i++) packet_send(i);
    fork
      packet_send(8'hac);
      begin
        wait(dut.received);@(negedge clk);valid=1;we=0;addr=4;
        #1;if(rdata!==0) $fatal(1,"FIFO first byte");
        @(negedge clk);valid=0;
      end
    join
    read_check(20,0);read_check(0,32'h2001);
    for(integer i=1;i<32;i++) read_check(4,i);
    read_check(4,8'hac);read_check(0,0);
    packet_send(8'h11);packet_send(8'h22);command(1);read_check(0,0);
    bit_send(0);bit_send(1);
    rst=1;pc=1;pd=1;repeat(20) @(negedge clk);rst=0;
    packet_send(8'h76);read_check(4,8'h76);read_check(0,0);
    $display("PS2 KEYBOARD PASS packets=%0d all256bytes parity stop start timeout filter FIFO overflow simultaneous-pop reset",packets);
    $finish;
  end
  initial begin #100000000;$fatal(1,"PS2 test timeout");end
endmodule
