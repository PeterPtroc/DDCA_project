`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_perf #(parameter PC_STYLE=0);
  localparam DIVIDER=16;
  reg clk=0,ui_clk=0,rst=1,uart_rx=1;
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
  integer cycles=0;
  integer uart_file,bit_index;
  reg [7:0] received;
  string line="";
  reg held=0;
  reg [68:0] held_payload;
  ptrocos_soc #(.IMEM_HEX("build/hex/ptrocos_perf.hex"),.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER)) dut (
      .ui_clk(ui_clk),.ui_rst(rst),.scan_araddr(),.scan_arlen(),.scan_arsize(),.scan_arburst(),
      .scan_arvalid(),.scan_arready(1'b0),.scan_rdata(128'd0),.scan_rresp(2'd0),
      .scan_rlast(1'b0),.scan_rvalid(1'b0),.scan_rready(),
      .clk(clk),.rst(rst),.sw(16'd0),.btn(5'd0),.uart_rx(uart_rx),.uart_tx(uart_tx),
      .sd_miso(1'b1),.sd_cd_n(1'b1),
      .pixel_clk(clk),.pixel_rst(rst),.ps2_clk(1'b1),.ps2_data(1'b1),
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
  axi_sparse_memory #(.CAPACITY(2048)) memory (
      .clk(ui_clk),.rst(rst),.awaddr(awaddr),.araddr(araddr),.awlen(awlen),.arlen(arlen),.awsize(awsize),.arsize(arsize),
      .awburst(awburst),.arburst(arburst),.awvalid(awvalid),.wvalid(wvalid),.wlast(wlast),.bready(bready),.arvalid(arvalid),.rready(rready),
      .wdata(wdata),.wstrb(wstrb),.awready(awready),.wready(wready),.arready(arready),.bvalid(bvalid),.rvalid(rvalid),
      .bresp(bresp),.rresp(rresp),.rlast(rlast),.rdata(rdata),.write_count(write_count),.read_count(read_count)
  );
  always #5 clk=~clk;
  // 使用周期互不整除的时钟，覆盖邮箱跨时钟域通信的各种相对相位。
  always #6.1535 ui_clk=~ui_clk;

  integer phase=-1,trace_file,metrics_file,seen=0;
  reg uart_pass=0;
  integer measured_cycles=0,measured_retired=0,bus_wait=0,ddr_wait=0;
  integer load_use=0,m_wait=0,reads=0,writes=0,mmio_requests=0,dma_reads=0,dma_writes=0;
  initial begin
    trace_file=$fopen($sformatf("build/ptrocos_perf/trace.style%0d.csv",PC_STYLE),"w");
    metrics_file=$fopen($sformatf("build/ptrocos_perf/metrics.style%0d.csv",PC_STYLE),"w");
    uart_file=$fopen($sformatf("build/ptrocos_perf/uart.style%0d.log",PC_STYLE),"w");
    if(!trace_file || !metrics_file || !uart_file) $fatal(1,"Performance output open");
    $fdisplay(trace_file,"phase,cycle,write,address");
    $fdisplay(metrics_file,"phase,cycles,retired,bus_wait,ddr_wait,load_use,m_wait,ddr_reads,ddr_writes,mmio_requests,dma_reads,dma_writes");
    repeat(8) @(negedge clk);rst=0;
  end
  always @(posedge clk) if(!rst) begin
    cycles++;
    if(cycles>5000000) $fatal(1,"Performance timeout pc=%x",dut.ia);
    if(trap || result[31:16]==16'hbad6) $fatal(1,"Performance firmware error cause=%x result=%x",cause,result);
    if(held && (!mv || {mw,ma,md,ms}!==held_payload)) $fatal(1,"Performance unstable word request");
    held<=mv && !mr;held_payload<={mw,ma,md,ms};
    if(dut.dv && dut.dwe && dut.data_ready && dut.da==32'h4000000c) begin
      if(dut.dw[31:16]==16'hcace) begin
        if(phase!=-1 || dut.dw[15:0]!=seen) $fatal(1,"Performance phase order");
        phase=dut.dw[15:0];
        measured_cycles=0;measured_retired=0;bus_wait=0;ddr_wait=0;load_use=0;m_wait=0;
        reads=0;writes=0;mmio_requests=0;dma_reads=0;dma_writes=0;
      end else if(dut.dw[31:16]==16'hcafe) begin
        if(phase!=dut.dw[15:0]) $fatal(1,"Performance phase stop");
        if(phase<4 && (reads || writes || ddr_wait)) $fatal(1,"Unexpected baseline DDR traffic");
        if((phase==4 || phase==5 || phase==7 || phase==8) && (reads!=1024 || writes)) $fatal(1,"Performance read accounting phase=%0d reads=%0d",phase,reads);
        if(phase==6 && (writes!=256 || reads)) $fatal(1,"Performance store accounting");
        if(phase==8 && (dma_reads!=256 || dma_writes!=256)) $fatal(1,"Performance DMA accounting");
        $fdisplay(metrics_file,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",phase,measured_cycles,measured_retired,bus_wait,ddr_wait,load_use,m_wait,reads,writes,mmio_requests,dma_reads,dma_writes);
        $display("PERF SOC CASE style=%0d phase=%0d cycles=%0d retired=%0d DDRwait=%0d reads=%0d writes=%0d",PC_STYLE,phase,measured_cycles,measured_retired,ddr_wait,reads,writes);
        phase=-1;seen++;
      end
    end
    if(phase>=0) begin
      measured_cycles++;if(dut.rv) measured_retired++;
      if(dut.dv && !dut.data_ready) bus_wait++;
      if(dut.dv && dut.ddr_sel && !dut.data_ready) ddr_wait++;
      if(dut.cpu.load_stall) load_use++;if(dut.cpu.m_wait) m_wait++;
      if(dut.dv && dut.data_ready && dut.mmio_sel) mmio_requests++;
      if(dut.dv && dut.ddr_sel && dut.data_ready) begin
        if(dut.dwe) writes++;else reads++;
        $fdisplay(trace_file,"%0d,%0d,%0d,%08x",phase,cycles,dut.dwe,dut.da);
      end
      if(dut.dma_valid && dut.dma_ready) begin
        if(dut.dma_we) dma_writes++;else dma_reads++;
      end
    end
    if(result==32'h600d600d && uart_pass) begin
      if(seen!=9 || phase!=-1) $fatal(1,"Performance coverage phases=%0d",seen);
      for(integer i=0;i<256;i++) if(memory.peek_word(27'h10000+i*4)!==17*i+3) $fatal(1,"Independent DMA result");
      $fclose(trace_file);$fclose(metrics_file);$fclose(uart_file);
      $display("PTROCOS PERF SOC PASS style=%0d cycles=%0d phases=%0d DDRreads=%0d DDRwrites=%0d",PC_STYLE,cycles,seen,read_count,write_count);
      $finish;
    end
  end
  initial forever begin
    @(negedge uart_tx);#(DIVIDER*10/2);
    if(uart_tx!==0) $fatal(1,"Performance UART start");
    for(bit_index=0;bit_index<8;bit_index++) begin #(DIVIDER*10);received[bit_index]=uart_tx;end
    #(DIVIDER*10);if(uart_tx!==1) $fatal(1,"Performance UART stop");
    $fwrite(uart_file,"%c",received);
    if(received==10) begin
      if(line=="PTROCOS PERF FIRMWARE PASS") uart_pass=1;
      $display("PERF UART style=%0d %s",PC_STYLE,line);line="";
    end
    else if(received!=13) line={line,received};
  end
endmodule
module tb_ptrocos_perf_alt;tb_ptrocos_perf #(.PC_STYLE(1)) test();endmodule
`default_nettype wire
