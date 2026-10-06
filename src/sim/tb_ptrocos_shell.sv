`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_shell #(parameter PC_STYLE=0);
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
  ptrocos_soc #(.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER),.IMEM_HEX("build/hex/ptrocos_shell.hex")) dut (
      .ui_clk(ui_clk),.ui_rst(rst),.scan_araddr(),.scan_arlen(),.scan_arsize(),.scan_arburst(),
      .scan_arvalid(),.scan_arready(1'b0),.scan_rdata(128'd0),.scan_rresp(2'd0),
      .scan_rlast(1'b0),.scan_rvalid(1'b0),.scan_rready(),
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
  reg booted=0,echo_ok=0,edit_ok=0,sleeping=0,cancelled=0,dma_ok=0,uptime_ok=0;
  integer yields=0,mtime_irqs=0,ticks_report=0,heartbeat_report=0,io_report=0,dropped_report=0;
  integer log_file;
  always @(posedge clk) if(!rst) begin
    cycles<=cycles+1;
    if(cycles>6000000) $fatal(1,"SHELL timeout pc=%x result=%x",dut.ia,result);
    if(trap) begin
      if(cause==11) yields++;
      else if(cause==32'h80000007) mtime_irqs++;
      else $fatal(1,"Unexpected shell trap %x",cause);
    end
    if(result[31:16]==16'hbad5) $fatal(1,"Shell panic %x",result);
  end
  initial begin
    log_file=$fopen(PC_STYLE==0 ? "build/ptrocos_shell/uart.style0.log" : "build/ptrocos_shell/uart.style1.log","w");
    if(!log_file) $fatal(1,"UART log open");
  end
  initial forever begin
    @(negedge uart_tx);#(DIVIDER*10/2);
    if(uart_tx!==0) $fatal(1,"UART start");
    for(bit_index=0;bit_index<8;bit_index++) begin #(DIVIDER*10);received[bit_index]=uart_tx;end
    #(DIVIDER*10);if(uart_tx!==1) $fatal(1,"UART stop");
    $fwrite(log_file,"%c",received);
    if(received==10) begin
      if(line=="PTROCOS SHELL READY") booted=1;
      if(line=="UART-OK") echo_ok=1;
      if(line=="abc") edit_ok=1;
      if(line=="sleeping; Ctrl+C cancels") sleeping=1;
      if(line=="^C cancelled") cancelled=1;
      if(line=="DDR DMA PASS words=256 crc=0000f364") dma_ok=1;
      if($sscanf(line,"ticks=%d heartbeat=%d io_polls=%d input_dropped=%d",ticks_report,heartbeat_report,io_report,dropped_report)==4) uptime_ok=1;
      if(line.len()<160) $display("SHELL UART style=%0d %s",PC_STYLE,line);
      line="";
    end else if(received!=13) line={line,received};
  end
  task uart_byte(input byte value);
    @(negedge clk);uart_rx=0;repeat(DIVIDER) @(negedge clk);
    for(integer i=0;i<8;i++) begin uart_rx=value[i];repeat(DIVIDER) @(negedge clk);end
    uart_rx=1;repeat(DIVIDER) @(negedge clk);
    // Service task is intentionally paced at the real 1 kHz tick frequency.
    repeat(4000) @(negedge clk);
  endtask
  task uart_text(input string value);
    for(integer i=0;i<value.len();i++) uart_byte(value[i]);
  endtask
  task ps2_bit(input bit value);
    @(negedge clk);ps2_data=value;repeat(60) @(negedge clk);ps2_clk=0;
    repeat(150) @(negedge clk);ps2_clk=1;repeat(150) @(negedge clk);
  endtask
  task scan(input byte value);
    ps2_bit(0);for(integer i=0;i<8;i++) ps2_bit(value[i]);
    ps2_bit(~^value);ps2_bit(1);ps2_data=1;repeat(40) @(negedge clk);
  endtask
  task shift_up;
    scan(8'hf0);scan(8'h12);
  endtask
  initial begin
    repeat(20) @(negedge clk);rst=0;wait(booted);
    uart_text("echo UART-OK\n");wait(echo_ok);
    uart_text("echo ac\033[Db\n");wait(edit_ok);
    uart_text("sleep 200\n");wait(sleeping);
    // VGA shell operates while the UART shell sleeps; input never goes to UART.
    scan(8'h24);scan(8'h21);scan(8'h33);scan(8'h44);scan(8'h29);
    scan(8'h12);scan(8'h2a);scan(8'h34);scan(8'h1c);shift_up();scan(8'h4e);
    scan(8'h12);scan(8'h44);scan(8'h42);shift_up();scan(8'h5a);
    repeat(2000000) @(negedge clk);
    if(dut.text_display.cells[160][7:0]!="V" || dut.text_display.cells[161][7:0]!="G" ||
       dut.text_display.cells[162][7:0]!="A" || dut.text_display.cells[163][7:0]!="-" ||
       dut.text_display.cells[164][7:0]!="O" || dut.text_display.cells[165][7:0]!="K")
      $fatal(1,"Independent VGA TTY did not execute echo while UART slept");
    uart_byte(3);wait(cancelled);
    uart_text("ddrtest\n");wait(dma_ok);
    uart_text("uptime\n");wait(uptime_ok);
    repeat(20000) @(negedge clk);
    if(result!==32'h600d7005 || yields<10 || mtime_irqs<20 || heartbeat_report<3 || io_report<20 || dropped_report)
      $fatal(1,"Scheduler coverage/result yields=%0d timer=%0d hb=%0d result=%x",yields,mtime_irqs,heartbeat_report,result);
    if(dut.keyboard.frame_count || dut.keyboard.timeout_total || dut.keyboard.overflow_count)
      $fatal(1,"PS2 errors in shell integration");
    $fclose(log_file);
    $display("PTROCOS SHELL SOC PASS style=%0d cycles=%0d yields=%0d timer=%0d heartbeat=%0d io=%0d AXIwrite=%0d AXIread=%0d independent-UART-and-VGA ctrl-c DMA",
      PC_STYLE,cycles,yields,mtime_irqs,heartbeat_report,io_report,write_count,read_count);
    $finish;
  end
endmodule
module tb_ptrocos_shell_alt;tb_ptrocos_shell #(.PC_STYLE(1)) test();endmodule
`default_nettype wire
