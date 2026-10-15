`timescale 1ns/1ps
`default_nettype none
// 使用完整地址标记的独立存储器，支持突发读取和单拍写入。
// 图案模式直接根据地址生成 RGB565 像素，用于显示扫描输出的单元测试。
module axi_graphics_memory #(parameter CAPACITY=131072,INITIAL_PATTERN=0) (
    input wire clk,rst,stall_reads,
    input wire [2:0] fault_mode,
    input wire [26:0] awaddr,araddr,
    input wire [7:0] awlen,arlen,
    input wire [2:0] awsize,arsize,
    input wire [1:0] awburst,arburst,
    input wire awvalid,wvalid,wlast,bready,arvalid,rready,
    input wire [127:0] wdata,
    input wire [15:0] wstrb,
    output wire awready,wready,arready,
    output reg bvalid=0,rvalid=0,
    output wire [1:0] bresp,
    output reg [1:0] rresp=0,
    output reg rlast=0,
    output reg [127:0] rdata=0,
    output integer write_count=0,read_count=0,burst_count=0
);
  reg occupied[0:CAPACITY-1];reg [22:0] tags[0:CAPACITY-1];reg [127:0] data[0:CAPACITY-1];
  integer cycle=0,bd=0,rd=0,j,index,lane;
  reg got_aw=0,got_w=0,reading=0;
  reg [26:0] saved_aw,read_address;
  reg [127:0] saved_data;
  reg [15:0] saved_strobes;
  integer read_total,read_index;
  reg [2:0] read_fault;
  initial for(integer i=0;i<CAPACITY;i++) occupied[i]=0;
  function automatic integer lookup(input [22:0] tag);
    integer position,first;
    begin
      position=((tag*32'h9e3779b1)^(tag>>11))&(CAPACITY-1);first=position;
      while(occupied[position] && tags[position]!=tag) begin
        position=(position+1)&(CAPACITY-1);
        if(position==first) $fatal(1,"Graphics memory hash table exhausted");
      end
      lookup=position;
    end
  endfunction
  function automatic [127:0] read_at(input [26:0] address);
    integer position,n;
    reg [15:0] pixel;
    begin
      position=lookup(address[26:4]);read_at=0;
      if(occupied[position]) read_at=data[position];
      else if(INITIAL_PATTERN) for(integer p=0;p<8;p++) begin
        n=((address+p*2)/2)^((address+p*2)/524288);
        pixel=(((n*3+1)&31)<<11)|(((n*5+7)&63)<<5)|((n*7+3)&31);
        read_at[p*16+:16]=pixel;
      end
    end
  endfunction
  function automatic [31:0] peek_word(input [26:0] address);
    reg [127:0] value;
    begin value=read_at({address[26:4],4'd0});peek_word=value>>(address[3:2]*32);end
  endfunction
  assign awready=!got_aw && !bvalid && !bd && cycle%5==1;
  assign wready=!got_w && !bvalid && !bd && cycle%7==3;
  assign arready=!reading && !rvalid && !stall_reads && cycle%4==2;
  assign bresp=0;
  always @(posedge clk) begin
    if(rst) begin
      for(j=0;j<CAPACITY;j++) occupied[j]=0;
      cycle<=0;bd<=0;rd<=0;got_aw<=0;got_w<=0;reading<=0;
      bvalid<=0;rvalid<=0;rdata<=0;rresp<=0;rlast<=0;
      write_count=0;read_count=0;burst_count=0;
    end else begin
      cycle<=cycle+1;
      if(awvalid && awready) begin
        if(awlen!=0 || awsize!=4 || awburst!=1 || awaddr[3:0]!=0) $fatal(1,"Graphics memory invalid AW");
        saved_aw<=awaddr;got_aw<=1;
      end
      if(wvalid && wready) begin
        if(!wlast) $fatal(1,"Graphics memory missing WLAST");
        saved_data<=wdata;saved_strobes<=wstrb;got_w<=1;
      end
      if(got_aw && got_w) begin
        index=lookup(saved_aw[26:4]);
        if(!occupied[index]) begin occupied[index]=1;tags[index]=saved_aw[26:4];data[index]=0;end
        for(lane=0;lane<16;lane++) if(saved_strobes[lane]) data[index][lane*8+:8]=saved_data[lane*8+:8];
        got_aw<=0;got_w<=0;bd<=6+cycle%3;write_count++;
      end
      if(bd>1) bd<=bd-1;
      else if(bd==1) begin bd<=0;bvalid<=1;end
      if(bvalid && bready) bvalid<=0;
      if(arvalid && arready) begin
        if(arsize!=4 || arburst!=1 || araddr[3:0]!=0 || arlen>15 ||
           {1'b0,araddr[11:0]}+((arlen+1)*16)>4096) $fatal(1,"Graphics memory invalid AR addr=%x len=%0d",araddr,arlen);
        read_address<=araddr;reading<=1;read_index<=0;read_total<=arlen+1;
        read_fault<=arlen ? fault_mode : 0;
        if(arlen && fault_mode==2) read_total<=arlen;
        if(arlen && fault_mode==3) read_total<=arlen+2;
        rd<=5+cycle%5;burst_count++;
      end
      if(reading && !rvalid && !stall_reads) begin
        if(rd>1) rd<=rd-1;
        else begin
          rd<=0;rdata<=read_at(read_address+read_index*16);
          rresp<=read_fault==1 && read_index==0 ? 2 : 0;
          rlast<=read_index==read_total-1;rvalid<=1;
        end
      end
      if(rvalid && rready) begin
        rvalid<=0;read_count++;
        if(rlast) reading<=0;
        else begin read_index<=read_index+1;rd<=1+cycle%3;end
      end
    end
  end
endmodule
`default_nettype wire
