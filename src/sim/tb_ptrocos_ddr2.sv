`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_ddr2 #(parameter PC_STYLE=0);
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
  integer cycles=0,load_faults=0,store_faults=0,timer_irqs=0;
  integer dma_reads=0,dma_writes=0,contention=0,irqs_during_dma=0,passes=0;
  integer uart_file,bit_index;
  reg [7:0] received;
  string line="";
  reg held=0;
  reg [68:0] held_payload;
  ptrocos_soc #(.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER)) dut (
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
  axi_sparse_memory memory (
      .clk(ui_clk),.rst(rst),.awaddr(awaddr),.araddr(araddr),.awlen(awlen),.arlen(arlen),.awsize(awsize),.arsize(arsize),
      .awburst(awburst),.arburst(arburst),.awvalid(awvalid),.wvalid(wvalid),.wlast(wlast),.bready(bready),.arvalid(arvalid),.rready(rready),
      .wdata(wdata),.wstrb(wstrb),.awready(awready),.wready(wready),.arready(arready),.bvalid(bvalid),.rvalid(rvalid),
      .bresp(bresp),.rresp(rresp),.rlast(rlast),.rdata(rdata),.write_count(write_count),.read_count(read_count)
  );
  always #5 clk=~clk;
  // Incommensurate clock periods exercise all relative phases of the mailbox.
  always #6.1535 ui_clk=~ui_clk;
  always @(posedge clk) if(!rst) begin
    cycles<=cycles+1;
    if(cycles>1500000) $fatal(1,"SoC firmware timeout pc=%08x result=%08x",dut.ia,result);
    if(result[31:20]==12'hbad) $fatal(1,"firmware failure %08x pc=%08x",result,dut.ia);
    if(held && (!mv || {mw,ma,md,ms}!==held_payload)) $fatal(1,"word request changed before completion");
    held<=mv && !mr;held_payload<={mw,ma,md,ms};
    if(dut.dma_valid && dut.dma_ready) begin
      if(dut.dma_we) dma_writes<=dma_writes+1;
      else dma_reads<=dma_reads+1;
    end
    if(dut.dma_valid && dut.dv && dut.ddr_sel) contention<=contention+1;
    if(trap) begin
      case(cause)
        5:load_faults<=load_faults+1;
        7:store_faults<=store_faults+1;
        32'h80000007:begin
          timer_irqs<=timer_irqs+1;
          if(dut.dma_valid) irqs_during_dma<=irqs_during_dma+1;
        end
        default:$fatal(1,"unexpected SoC trap %08x",cause);
      endcase
    end
  end
  // Decode the actual serial pin, including its stop bit.
  initial forever begin
    @(negedge uart_tx);
    if(!rst) begin
      repeat(DIVIDER+DIVIDER/2) @(posedge clk);
      for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
        received[bit_index]=uart_tx;
        repeat(DIVIDER) @(posedge clk);
      end
      if(uart_tx!==1) $fatal(1,"UART framing error");
      $write("%c",received);$fwrite(uart_file,"%c",received);
      if(received==10) begin
        if(line=="DDR2 DMA PASS") passes=passes+1;
        if(line.substr(0,12)=="DDR2 DMA FAIL") $fatal(1,"UART reports firmware failure");
        line="";
      end else line={line,received};
    end
  end
  task send_byte(input [7:0] value);
    integer j;
    begin
      @(negedge clk);uart_rx=0;repeat(DIVIDER) @(negedge clk);
      for(j=0;j<8;j=j+1) begin uart_rx=value[j];repeat(DIVIDER) @(negedge clk);end
      uart_rx=1;repeat(2*DIVIDER) @(negedge clk);
    end
  endtask
  integer i;
  reg [31:0] expected;
  initial begin
    uart_file=$fopen(PC_STYLE ? "build/ptrocos_ddr2/uart.style1.log" : "build/ptrocos_ddr2/uart.style0.log","w");
    repeat(8) @(negedge clk);rst=0;
    wait(result==32'h600d600d && passes==1);
    repeat(8000) @(negedge clk);
    send_byte("r");
    wait(passes==2);
    repeat(100) @(negedge clk);
    if(load_faults!=2 || store_faults!=2 || timer_irqs<2 || irqs_during_dma<1)
      $fatal(1,"trap coverage load=%0d store=%0d timer=%0d DMA_irq=%0d",load_faults,store_faults,timer_irqs,irqs_during_dma);
    if(dma_reads!=512 || dma_writes!=512 || contention<1)
      $fatal(1,"DMA accounting read=%0d write=%0d contention=%0d",dma_reads,dma_writes,contention);
    for(i=0;i<256;i=i+1) begin
      expected=(i*32'h9e3779b9)^32'ha55a1357;
      if(memory.peek_word(27'h1000+4*i)!==expected || memory.peek_word(27'h2000+4*i)!==expected)
        $fatal(1,"DMA independent memory mismatch word=%0d",i);
    end
    if(memory.peek_word(27'h7fffffc)!==((32'h1ffffff*32'h9e3779b9)^32'ha55a1357))
      $fatal(1,"upper DDR address lost");
    $fclose(uart_file);
    $display("PTROCOS DDR2 SOC PASS style=%0d cycles=%0d DMA_reads=%0d DMA_writes=%0d timer=%0d DMA_irq=%0d contention=%0d AXI_writes=%0d AXI_reads=%0d",
        PC_STYLE,cycles,dma_reads,dma_writes,timer_irqs,irqs_during_dma,contention,write_count,read_count);
    $finish;
  end
endmodule
module tb_ptrocos_ddr2_alt;
  tb_ptrocos_ddr2 #(.PC_STYLE(1)) test();
endmodule
`default_nettype wire
