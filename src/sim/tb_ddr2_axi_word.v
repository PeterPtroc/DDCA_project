`default_nettype none
module tb_ddr2_axi_word;
  reg clk=0, rst=1, valid=0, we=0;
  reg [31:0] addr=0, wdata=0;
  reg [3:0] wstrb=0;
  wire ready, error;
  wire [31:0] rdata;
  wire [26:0] awaddr, araddr;
  wire [7:0] awlen, arlen;
  wire [2:0] awsize, arsize;
  wire [1:0] awburst, arburst;
  wire awvalid, wvalid, bready, arvalid, rready, wlast;
  wire [127:0] wd;
  wire [15:0] ws;
  reg [127:0] rd=0;
  reg [1:0] bresp=0, rresp=0;
  reg bvalid=0, rvalid=0;
  integer cycle=0, bdelay=0, rdelay=0, commands=0, tests=0;
  reg got_aw=0, got_w=0;
  wire awready = (cycle % 5 == 1 || cycle % 5 == 4) && !got_aw;
  wire wready = (cycle % 7 == 2 || cycle % 7 == 5) && !got_w;
  wire arready = cycle % 4 == 3 && !rdelay && !rvalid;
  reg [26:0] write_addr;
  reg [127:0] write_data;
  reg [15:0] write_strobes;
  reg [7:0] memory[0:255], expected_memory[0:255];
  reg inject_error=0;
  integer i, lane, mask, before_commands, timeout;
  reg [31:0] expected_word;
  ddr2_axi_word_bridge dut (
      .clk(clk), .rst(rst), .valid(valid), .we(we), .addr(addr), .wdata(wdata),
      .wstrb(wstrb), .ready(ready), .rdata(rdata), .error(error),
      .axi_awaddr(awaddr), .axi_awlen(awlen), .axi_awsize(awsize), .axi_awburst(awburst),
      .axi_awvalid(awvalid), .axi_awready(awready), .axi_wdata(wd), .axi_wstrb(ws),
      .axi_wlast(wlast), .axi_wvalid(wvalid), .axi_wready(wready),
      .axi_bresp(bresp), .axi_bvalid(bvalid), .axi_bready(bready),
      .axi_araddr(araddr), .axi_arlen(arlen), .axi_arsize(arsize), .axi_arburst(arburst),
      .axi_arvalid(arvalid), .axi_arready(arready), .axi_rdata(rd),
      .axi_rresp(rresp), .axi_rlast(1'b1), .axi_rvalid(rvalid), .axi_rready(rready)
  );
  always #5 clk=~clk;
  // 独立的字节寻址存储器，AW/W 通道可独立停顿，B/R 通道带有延迟。
  always @(posedge clk) if (!rst) begin
    cycle<=cycle+1;
    if (awvalid && awready) begin
      if (awlen != 0 || awsize != 4 || awburst != 1 || awaddr[3:0] != 0) $fatal(1, "invalid AXI write shape");
      write_addr <= awaddr; got_aw <= 1; commands=commands+1;
    end
    if (wvalid && wready) begin
      if (!wlast) $fatal(1, "missing AXI WLAST");
      write_data <= wd; write_strobes <= ws; got_w <= 1;
    end
    if (got_aw && got_w) begin
      for (i=0; i<16; i=i+1)
        if (write_strobes[i]) memory[{write_addr[7:4],4'b0000}+i] <= write_data[8*i +: 8];
      got_aw <= 0; got_w <= 0; bdelay <= 6;
      bresp <= inject_error ? 2'b10 : 0;
    end
    if (bdelay > 1) bdelay <= bdelay-1;
    else if (bdelay == 1) begin bdelay<=0; bvalid<=1; end
    if (bvalid && bready) bvalid<=0;
    if (arvalid && arready) begin
      if (arlen != 0 || arsize != 4 || arburst != 1 || araddr[3:0] != 0) $fatal(1, "invalid AXI read shape");
      for (i=0; i<16; i=i+1) rd[8*i +: 8] <= memory[{araddr[7:4],4'b0000}+i];
      rdelay<=5; rresp<=inject_error ? 2'b10 : 0; commands=commands+1;
    end
    if (rdelay > 1) rdelay <= rdelay-1;
    else if (rdelay == 1) begin rdelay<=0; rvalid<=1; end
    if (rvalid && rready) rvalid<=0;
  end
  task access;
    input write_request;
    input [31:0] address, value;
    input [3:0] byte_mask;
    input expected_error;
    begin
      @(negedge clk);
      valid=1; we=write_request; addr=address; wdata=value; wstrb=byte_mask;
      timeout=0;
      while (!ready && timeout<100) begin @(negedge clk); timeout=timeout+1; end
      if (!ready || error !== expected_error) $fatal(1, "DDR word completion/error mismatch");
      if (address[31:27] == 5'b10000) begin
        if (write_request) begin
          for (lane=0; lane<4; lane=lane+1)
            if (byte_mask[lane]) expected_memory[{address[7:2],2'b00}+lane]=value[8*lane +: 8];
        end else if (!expected_error) begin
          expected_word={expected_memory[{address[7:2],2'b00}+3], expected_memory[{address[7:2],2'b00}+2],
                         expected_memory[{address[7:2],2'b00}+1], expected_memory[{address[7:2],2'b00}]};
          if (rdata !== expected_word) $fatal(1, "wrong DDR word lane got=%08x expected=%08x", rdata, expected_word);
        end
      end
      @(negedge clk); valid=0;
      for (lane=0; lane<256; lane=lane+1)
        if (memory[lane] !== expected_memory[lane]) $fatal(1, "DDR corrupted adjacent byte %0d", lane);
      tests=tests+1;
      @(negedge clk);
    end
  endtask
  integer word_lane;
  initial begin
    for(i=0;i<256;i=i+1) begin memory[i]=i; expected_memory[i]=i; end
    repeat(4) @(negedge clk); rst=0;
    for(word_lane=0;word_lane<4;word_lane=word_lane+1)
      for(mask=0;mask<16;mask=mask+1) begin
        access(1,32'h80000000+4*word_lane,32'h87654321 ^ mask,mask,0);
        access(0,32'h80000000+4*word_lane,0,0,0);
      end
    access(1,32'h87fffffc,32'h12345678,4'hf,0);
    access(0,32'h87fffffc,0,0,0);
    inject_error=1;
    access(1,32'h80000020,32'hdeadbeef,4'hf,1);
    access(0,32'h80000020,0,0,1);
    inject_error=0;
    before_commands=commands;
    access(1,32'h88000000,32'hbad,4'hf,1);
    access(0,32'h7ffffffc,0,0,1);
    if(commands!=before_commands) $fatal(1, "out-of-range DDR request reached AXI");
    access(0,32'h80000020,0,0,0);
    $display("DDR2 AXI WORD PASS: %0d transactions; lanes, all strobes, independent AW/W, delayed responses, errors and bounds",tests);
    $finish;
  end
endmodule
`default_nettype wire
