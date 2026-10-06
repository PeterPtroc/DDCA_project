`timescale 1ns/1ps
`default_nettype none
module tb_sd_spi;
  reg clk=0,rst=1,valid=0,we=0,miso=1,cd_n=1;
  reg [31:0] addr=0,wdata=0;
  reg [3:0] wstrb=0;
  wire [31:0] rdata;
  wire sck,mosi,cs_n,power_off;
  sd_spi dut(.clk(clk),.rst(rst),.valid(valid),.we(we),.addr(addr),.wdata(wdata),.wstrb(wstrb),.rdata(rdata),
      .sd_miso(miso),.sd_cd_n(cd_n),.sd_sck(sck),.sd_mosi(mosi),.sd_cs_n(cs_n),.sd_reset(power_off));
  always #5 clk=~clk;
  integer cycles=0,edges=0,bytes=0,half_cycles=0,last_edge=0,expected_half=125,index=0;
  reg checking=0;
  reg [7:0] outgoing=0,incoming=0;
  always @(posedge clk) begin
    cycles++;
    if(cycles>1000000) $fatal(1,"SD SPI timeout");
  end
  always @(posedge sck or negedge sck) if(checking) begin
    if(last_edge && cycles-last_edge!=expected_half)
      $fatal(1,"SCK half period got=%0d expected=%0d",cycles-last_edge,expected_half);
    last_edge=cycles;edges++;
    if(sck) begin
      if(mosi!==outgoing[7-index]) $fatal(1,"MOSI order at bit %0d",index);
      index++;
    end else if(index<8) miso=incoming[7-index];
  end
  task write_reg(input [31:0] off,data,input [3:0] strobes);
    @(negedge clk);addr=off;wdata=data;wstrb=strobes;valid=1;we=1;
    @(negedge clk);valid=0;we=0;wstrb=0;
  endtask
  task read_equal(input [31:0] off,expected);
    @(negedge clk);addr=off;#1;if(rdata!==expected) $fatal(1,"MMIO off=%x got=%x expected=%x",off,rdata,expected);
  endtask
  task exchange(input [7:0] send_byte,reply_byte,input integer half_period,input bit reconfigure);
    outgoing=send_byte;incoming=reply_byte;expected_half=half_period;
    edges=0;index=0;last_edge=0;miso=reply_byte[7];
    repeat(4) @(negedge clk);checking=1;
    write_reg(0,send_byte,1);
    if(reconfigure) write_reg(12,4,3);
    wait(!dut.busy);@(negedge clk);checking=0;bytes++;
    if(edges!=16 || index!=8 || sck!==0 || mosi!==1) $fatal(1,"SPI edge count/idling");
    read_equal(0,reply_byte);
    if(!dut.done || dut.fault) $fatal(1,"SPI completion state");
  endtask
  integer i;
  initial begin
    repeat(4) @(negedge clk);rst=0;
    read_equal(12,125);if(!power_off || !cs_n || sck) $fatal(1,"Reset outputs");
    write_reg(0,8'ha5,1);if(!dut.fault || dut.busy) $fatal(1,"Unpowered rejection");
    cd_n=0;repeat(4) @(negedge clk);write_reg(8,9,1);
    if(power_off || !cs_n) $fatal(1,"Power/startup clocks selection");
    exchange(8'hff,8'hff,125,0); // CS remains high during startup clocks.
    write_reg(8,3,1);if(cs_n) $fatal(1,"Select");
    exchange(8'h96,8'h69,125,1); // Divider changes apply to the next byte.
    for(i=0;i<256;i++) exchange(i[7:0],8'hff-i[7:0],4,0);
    write_reg(12,0,3);read_equal(12,4); // Clamp prevents sampling too early.
    write_reg(12,16'h012c,3);read_equal(12,300);
    write_reg(12,8'hf4,1);read_equal(12,500);
    exchange(8'ha5,8'h5a,500,0);
    write_reg(0,8'h12,2);if(dut.busy) $fatal(1,"Upper strobe started transfer");
    write_reg(0,8'h12,1);write_reg(0,8'h34,1);
    if(!dut.fault) $fatal(1,"Busy write rejection");
    write_reg(8,7,1);if(dut.busy || !dut.aborted || sck || mosi!==1) $fatal(1,"Abort");
    write_reg(8,11,1);if(dut.done || dut.fault || dut.aborted) $fatal(1,"Clear status");
    write_reg(0,8'h12,1);cd_n=1;repeat(5) @(negedge clk);
    if(dut.busy || !dut.fault || !dut.aborted || !cs_n || sck) $fatal(1,"Removal abort");
    write_reg(0,8'h34,1);if(dut.busy) $fatal(1,"Absent card started transfer");
    cd_n=0;repeat(4) @(negedge clk);write_reg(8,11,1);
    exchange(8'h24,8'h81,500,0);
    write_reg(0,8'h12,1);write_reg(8,0,1);
    if(dut.busy || !power_off || !cs_n || sck) $fatal(1,"Power-off abort");
    read_equal(16,bytes);
    rst=1;repeat(2) @(negedge clk);rst=0;read_equal(16,0);read_equal(0,255);
    $display("SD SPI UNIT PASS bytes=%0d all-byte-values mode0 strobes divider-latch busy-reject abort removal power reset",bytes);
    $finish;
  end
endmodule
`default_nettype wire
