`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_text #(parameter PC_STYLE=0);
  localparam DIVIDER=16;
  reg clk=0,ui_clk=0,pclk=0,rst=1,uart_rx=1,ps2_clk=1,ps2_data=1;
  wire uart_tx,mv,mw,mr,me,tv,tw,tr,te,trap;
  wire [31:0] ma,md,rd,ta,td,rr,cause,result;
  wire [3:0] ms,ts;
  wire [26:0] awaddr,araddr;
  wire [7:0] awlen,arlen;
  wire [2:0] awsize,arsize;
  wire [1:0] awburst,arburst,bresp,rresp;
  wire awvalid,awready,wvalid,wready,wlast,bvalid,bready,arvalid,arready,rvalid,rready,rlast;
  wire [127:0] wdata,rdata;
  wire [15:0] wstrb;
  wire [31:0] write_count,read_count;
  integer cycles=0,load_faults=0,store_faults=0,timer_irqs=0;
  integer dma_reads=0,dma_writes=0,contention=0,irqs_during_dma=0,passes=0;
  integer uart_file,bit_index;
  reg [7:0] received;
  string line="";
  reg held=0;
  reg [68:0] held_payload;
  ptrocos_soc #(.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER),.IMEM_HEX("build/hex/ptrocos_text.hex")) dut (
      .clk(clk),.rst(rst),.sw(16'd0),.btn(5'd0),.capture_in(8'd0),.uart_rx(uart_rx),.uart_tx(uart_tx),
      .sd_miso(1'b1),.sd_cd_n(1'b1),
      .pixel_clk(pclk),.pixel_rst(rst),.ps2_clk(ps2_clk),.ps2_data(ps2_data),
      .led(),.seg_an(),.seg(),.seg_dp(),.rgb0_r(),.rgb0_g(),.rgb0_b(),.rgb1_r(),.rgb1_g(),.rgb1_b(),
      .memory_valid(mv),.memory_we(mw),.memory_addr(ma),.memory_wdata(md),.memory_wstrb(ms),
      .memory_ready(mr),.memory_rdata(rd),.memory_error(me),.trap_taken(trap),.trap_cause(cause),.firmware_result(result)
  );
  word_bus_cdc cdc (
      .source_clk(clk),.source_rst(rst),.source_valid(mv),.source_we(mw),.source_addr(ma),.source_wdata(md),
      .source_wstrb(ms),.source_ready(mr),.source_rdata(rd),.source_error(me),
      .target_clk(ui_clk),.target_rst(rst),.target_valid(tv),.target_we(tw),.target_addr(ta),.target_wdata(td),
      .target_wstrb(ts),.target_ready(tr),.target_rdata(rr),.target_error(te)
  );
  ddr2_axi_word_bridge bridge (
      .clk(ui_clk),.rst(rst),.valid(tv),.we(tw),.addr(ta),.wdata(td),.wstrb(ts),.ready(tr),.rdata(rr),.error(te),
      .axi_awaddr(awaddr),.axi_awlen(awlen),.axi_awsize(awsize),.axi_awburst(awburst),.axi_awvalid(awvalid),.axi_awready(awready),
      .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wlast(wlast),.axi_wvalid(wvalid),.axi_wready(wready),
      .axi_bresp(bresp),.axi_bvalid(bvalid),.axi_bready(bready),
      .axi_araddr(araddr),.axi_arlen(arlen),.axi_arsize(arsize),.axi_arburst(arburst),.axi_arvalid(arvalid),.axi_arready(arready),
      .axi_rdata(rdata),.axi_rresp(rresp),.axi_rlast(rlast),.axi_rvalid(rvalid),.axi_rready(rready)
  );
  axi_sparse_memory memory (
      .clk(ui_clk),.rst(rst),.awaddr(awaddr),.araddr(araddr),.awlen(awlen),.arlen(arlen),.awsize(awsize),.arsize(arsize),
      .awburst(awburst),.arburst(arburst),.awvalid(awvalid),.wvalid(wvalid),.wlast(wlast),.bready(bready),.arvalid(arvalid),.rready(rready),
      .wdata(wdata),.wstrb(wstrb),.awready(awready),.wready(wready),.arready(arready),.bvalid(bvalid),.rvalid(rvalid),
      .bresp(bresp),.rresp(rresp),.rlast(rlast),.rdata(rdata),.write_count(write_count),.read_count(read_count)
  );
  always #5 clk=~clk;
  always #6.1535 ui_clk=~ui_clk;
  always #19.84127 pclk=~pclk;
  integer keys=0,reg_waits=0,cell_writes=0;
  reg booted=0;
  integer expected[0:8]='{97,65,65,97,3,256,10,8,47};
  integer decoded;
  always @(posedge clk) if(!rst) begin
    cycles<=cycles+1;
    if(cycles>4000000) $fatal(1,"TEXT SoC timeout pc=%x result=%x",dut.ia,result);
    if(trap) begin
      if(cause!=32'h80000007) $fatal(1,"Unexpected text trap %x",cause);
      timer_irqs++;
    end
    if(dut.dv && dut.vga_reg_sel && !dut.data_ready) reg_waits++;
    if(dut.dv && dut.vga_cell_sel && dut.dwe) cell_writes++;
    if(result[31:16]==16'hbad1) $fatal(1,"Text firmware failed %x",result);
  end
  initial forever begin
    @(negedge uart_tx);#(DIVIDER*10/2);
    if(uart_tx!==0) $fatal(1,"UART start");
    for(bit_index=0;bit_index<8;bit_index++) begin #(DIVIDER*10);received[bit_index]=uart_tx;end
    #(DIVIDER*10);if(uart_tx!==1) $fatal(1,"UART stop");
    if(received==10) begin
      $display("TEXT UART style=%0d %s",PC_STYLE,line);
      if(line=="TEXT PS2 READY") booted=1;
      else if(line.len()>=4 && line.substr(0,3)=="KEY ") begin
        if($sscanf(line,"KEY %h",decoded)!=1 || keys>=9 || decoded!=expected[keys])
          $fatal(1,"Key mismatch index=%0d decoded=%x",keys,decoded);
        keys++;
      end else if(line.len()>=13 && line.substr(0,12)=="TEXT PS2 FAIL") $fatal(1,"Firmware UART FAIL");
      line="";
    end else line={line,received};
  end
  task ps2_bit(input bit value);
    @(negedge clk);ps2_data=value;repeat(60) @(negedge clk);ps2_clk=0;
    repeat(150) @(negedge clk);ps2_clk=1;repeat(150) @(negedge clk);
  endtask
  task scan(input byte value);
    ps2_bit(0);for(integer i=0;i<8;i++) ps2_bit(value[i]);
    ps2_bit(~^value);ps2_bit(1);ps2_data=1;repeat(40) @(negedge clk);
  endtask
  task release_key(input byte value);
    scan(8'hf0);scan(value);
  endtask
  initial begin
    repeat(20) @(negedge clk);rst=0;
    wait(booted && result==32'h600d7004);
    scan(8'h1c);release_key(8'h1c);
    scan(8'h12);scan(8'h1c);release_key(8'h12);
    scan(8'h58);release_key(8'h58);scan(8'h1c);
    scan(8'h12);scan(8'h1c);release_key(8'h12);
    scan(8'h58);release_key(8'h58);
    scan(8'h14);scan(8'h21);release_key(8'h14);
    scan(8'he0);scan(8'h75);scan(8'he0);release_key(8'h75);
    scan(8'he1);scan(8'h14);scan(8'h77);scan(8'he1);scan(8'hf0);scan(8'h14);scan(8'hf0);scan(8'h77);
    scan(8'he0);scan(8'h12);scan(8'he0);scan(8'h7c);
    scan(8'he0);scan(8'hf0);scan(8'h7c);scan(8'he0);scan(8'hf0);scan(8'h12);
    scan(8'h5a);scan(8'h66);scan(8'h4a);
    wait(keys==9);repeat(2000) @(negedge clk);
    if(timer_irqs<15 || reg_waits<100 || cell_writes<4800) $fatal(1,"Missing CPU/VGA/IRQ coverage");
    if(dut.keyboard.frame_count || dut.keyboard.timeout_total || dut.keyboard.overflow_count)
      $fatal(1,"Unexpected PS2 transport errors");
    if(dut.text_display.cells[399]!==16'h072f || dut.text_display.cells[320]!==16'h0761) $fatal(1,"Keyboard echo did not reach VRAM");
    if(write_count<48 || read_count<32) $fatal(1,"DDR/DMA coverage missing");
    $display("PTROCOS TEXT SOC PASS style=%0d keys=%0d irq=%0d register-wait-cycles=%0d cell-writes=%0d AXIwrite=%0d AXIread=%0d cycles=%0d",
      PC_STYLE,keys,timer_irqs,reg_waits,cell_writes,write_count,read_count,cycles);
    $finish;
  end
endmodule
module tb_ptrocos_text_alt;tb_ptrocos_text #(.PC_STYLE(1)) test();endmodule
`default_nettype wire
