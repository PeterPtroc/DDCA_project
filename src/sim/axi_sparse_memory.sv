`timescale 1ns/1ps
`default_nettype none
// 仅用于仿真的独立稀疏存储器，容量为 128 MiB。使用完整字节地址
// 标记存储项，高位地址不会发生别名映射。AW/W 和 B/R 通道的延迟相互独立。
module axi_sparse_memory # (parameter CAPACITY=512) (
    input wire clk, rst,
    input wire [26:0] awaddr, araddr,
    input wire [7:0] awlen, arlen,
    input wire [2:0] awsize, arsize,
    input wire [1:0] awburst, arburst,
    input wire awvalid, wvalid, wlast, bready, arvalid, rready,
    input wire [127:0] wdata,
    input wire [15:0] wstrb,
    output wire awready, wready, arready,
    output reg bvalid=0, rvalid=0,
    output wire [1:0] bresp, rresp,
    output wire rlast,
    output reg [127:0] rdata=0,
    output integer write_count=0, read_count=0
);
  reg [22:0] tags[0:CAPACITY-1];
  reg [127:0] bytes[0:CAPACITY-1];
  integer used=0, cycle=0, bdelay=0, rdelay=0, index, lane;
  reg got_aw=0, got_w=0;
  reg [26:0] saved_addr;
  reg [127:0] saved_data;
  reg [15:0] saved_strobes;
  assign awready=!got_aw && !bvalid && !bdelay && cycle%5==1;
  assign wready=!got_w && !bvalid && !bdelay && cycle%7==3;
  assign arready=!rvalid && !rdelay && cycle%4==2;
  assign bresp=0, rresp=0, rlast=1;
  function automatic integer find(input [22:0] tag);
    integer j;
    begin
      find=-1;
      for(j=0;j<used;j=j+1) if(tags[j]==tag) find=j;
    end
  endfunction
  function automatic [31:0] peek_word(input [26:0] address);
    integer j;
    begin
      j=find(address[26:4]);
      peek_word=j<0 ? 0 : bytes[j][32*address[3:2] +: 32];
    end
  endfunction
  always @(posedge clk) begin
    if(rst) begin
      used=0;cycle<=0;bdelay<=0;rdelay<=0;got_aw<=0;got_w<=0;
      bvalid<=0;rvalid<=0;rdata<=0;write_count=0;read_count=0;
    end else begin
      cycle<=cycle+1;
      if(awvalid && awready) begin
        if(awlen!=0 || awsize!=4 || awburst!=1 || awaddr[3:0]!=0)
          $fatal(1,"invalid AXI AW shape");
        saved_addr<=awaddr;got_aw<=1;
      end
      if(wvalid && wready) begin
        if(!wlast) $fatal(1,"missing AXI WLAST");
        saved_data<=wdata;saved_strobes<=wstrb;got_w<=1;
      end
      if(got_aw && got_w) begin
        index=find(saved_addr[26:4]);
        if(index<0) begin
          if(used==CAPACITY) $fatal(1,"sparse memory exhausted");
          index=used;used=used+1;tags[index]=saved_addr[26:4];bytes[index]=0;
        end
        for(lane=0;lane<16;lane=lane+1)
          if(saved_strobes[lane]) bytes[index][8*lane +: 8]=saved_data[8*lane +: 8];
        write_count=write_count+1;got_aw<=0;got_w<=0;bdelay<=6+cycle%3;
      end
      if(bdelay>1) bdelay<=bdelay-1;
      else if(bdelay==1) begin bdelay<=0;bvalid<=1;end
      if(bvalid && bready) bvalid<=0;
      if(arvalid && arready) begin
        if(arlen!=0 || arsize!=4 || arburst!=1 || araddr[3:0]!=0)
          $fatal(1,"invalid AXI AR shape");
        index=find(araddr[26:4]);rdata<=index<0 ? 128'd0 : bytes[index];
        read_count=read_count+1;rdelay<=5+cycle%5;
      end
      if(rdelay>1) rdelay<=rdelay-1;
      else if(rdelay==1) begin rdelay<=0;rvalid<=1;end
      if(rvalid && rready) rvalid<=0;
    end
  end
endmodule
`default_nettype wire
