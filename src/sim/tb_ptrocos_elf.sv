`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_elf #(parameter PC_STYLE=0);
  localparam DIVIDER=16;
  reg clk=0,ui_clk=0,pclk=0,rst=1,uart_rx=1;
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
  wire sd_miso,sd_sck,sd_mosi,sd_cs_n,sd_reset;
  reg attached=1,corrupt=0;
  wire [31:0] sd_commands,sd_reads,sd_writes,power_cycles;
  sd_spi_card_model #(.IMAGE("build/ptrocos_elf/elf-fat16.hex")) card (
      .sck(sd_sck),.mosi(sd_mosi),.cs_n(sd_cs_n),.power_off(sd_reset),.attached(attached),
      .corrupt_next_read(corrupt),.miso(sd_miso),.commands(sd_commands),.reads(sd_reads),
      .writes(sd_writes),.power_cycles(power_cycles));
  ptrocos_elf_soc #(.IMEM_HEX("build/hex/ptrocos_elf.hex"),.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER)) dut (
      .ui_clk(ui_clk),.ui_rst(rst),.scan_araddr(),.scan_arlen(),.scan_arsize(),.scan_arburst(),
      .scan_arvalid(),.scan_arready(1'b0),.scan_rdata(128'd0),.scan_rresp(2'd0),
      .scan_rlast(1'b0),.scan_rvalid(1'b0),.scan_rready(),
      .clk(clk),.rst(rst),.sw(16'd0),.btn(5'd0),.uart_rx(uart_rx),.uart_tx(uart_tx),
      .sd_miso(sd_miso),.sd_cd_n(!attached),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_cs_n(sd_cs_n),.sd_reset(sd_reset),
      .pixel_clk(pclk),.pixel_rst(rst),.ps2_clk(1'b1),.ps2_data(1'b1),
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
  // Incommensurate clock periods exercise all relative phases of the mailbox.
  always #6.1535 ui_clk=~ui_clk;

  always #19.84127 pclk=~pclk;
  integer booted=0,tests=0,hello=0,returned=0,faulted=0,timedout=0,cancelled=0,mounted=0,load_errors=0,missing=0,dma_ok=0,uptime=0;
  integer timer_irqs=0,yields=0,illegal=0,app_retired=0;
  reg [31:0] architectural[0:31],saved_registers[0:31],call_reference[0:1];
  integer call_count=0,return_count=0;reg call_active=0;
  initial begin
    $readmemh("build/ptrocos_elf/call-reference.hex",call_reference);
    for(integer i=0;i<32;i++) begin architectural[i]=0;saved_registers[i]=0;end
  end
  always @(posedge clk) if(!rst && dut.rv) begin
    if(dut.rwe && dut.rr!=0) architectural[dut.rr]=dut.rd;
    if(dut.rpc==call_reference[0]) begin
      if(call_active) $fatal(1,"Nested ELF invocation");
      for(integer i=0;i<32;i++) saved_registers[i]=architectural[i];
      call_active=1;call_count++;
    end
    if(dut.rpc==call_reference[1]) begin
      if(!call_active) $fatal(1,"ELF return without invocation");
      for(integer i=1;i<32;i++)
        if(i<=4 || i==8 || i==9 || (i>=18 && i<=27))
          if(architectural[i]!==saved_registers[i]) $fatal(1,"ELF kernel register x%0d restore got=%x expected=%x",i,architectural[i],saved_registers[i]);
      call_active=0;return_count++;
    end
  end
  integer ticks,heartbeat,polls,dropped;
  initial begin
    uart_file=$fopen($sformatf("build/ptrocos_elf/uart.style%0d.log",PC_STYLE),"w");
    if(!uart_file) $fatal(1,"ELF log open");
  end
  always @(posedge clk) if(!rst) begin
    cycles++;
    if(cycles>20000000) $fatal(1,"ELF timeout pc=%x tests=%0d returned=%0d faulted=%0d",dut.ia,tests,returned,faulted);
    if(result[31:16]==16'hbad5) $fatal(1,"ELF kernel panic %x PC=%x",result,dut.ia);
    if(trap) begin
      if(cause==11) yields++;
      else if(cause==32'h80000007) timer_irqs++;
      else if(cause==2) illegal++;
      else $fatal(1,"ELF unexpected trap cause=%x",cause);
    end
    if(dut.rv && dut.rpc>=32'h10000 && dut.rpc<32'h14000) app_retired++;
    if(held && (!mv || {mw,ma,md,ms}!==held_payload)) $fatal(1,"ELF unstable DDR request");
    held<=mv && !mr;held_payload<={mw,ma,md,ms};
  end
  initial forever begin
    @(negedge uart_tx);#(DIVIDER*10/2);
    if(uart_tx!==0) $fatal(1,"ELF UART start");
    for(bit_index=0;bit_index<8;bit_index++) begin #(DIVIDER*10);received[bit_index]=uart_tx;end
    #(DIVIDER*10);if(uart_tx!==1) $fatal(1,"ELF UART stop");$fwrite(uart_file,"%c",received);
    if(received==10) begin
      if(line=="PTROCOS SHELL READY") booted++;
      if(line=="ELF TEST PASS hello reload-BSS fault timeout shell-return") tests++;
      if(line=="ELF TEST FAILED") $fatal(1,"ELF diagnostic failure");
      if(line=="ELF HELLO BSS PASS") hello++;
      if(line=="ELF returned code=37") returned++;
      if(line.substr(0,15)=="ELF fault cause=") faulted++;
      if(line=="ELF timeout") timedout++;
      if(line=="^C cancelled") cancelled++;
      if(line.substr(0,10)=="FAT mounted") mounted++;
      if(line.substr(0,14)=="ELF load error=") load_errors++;
      if(line=="mount the SD card first") missing++;
      if(line=="DDR DMA PASS words=256 crc=0000f364") dma_ok++;
      if($sscanf(line,"ticks=%d heartbeat=%d io_polls=%d input_dropped=%d",ticks,heartbeat,polls,dropped)==4) uptime++;
      $display("ELF UART style=%0d %s",PC_STYLE,line);line="";
    end else if(received!=13) line={line,received};
  end
  task uart_byte(input byte value);
    @(negedge clk);uart_rx=0;repeat(DIVIDER) @(negedge clk);
    for(integer i=0;i<8;i++) begin uart_rx=value[i];repeat(DIVIDER) @(negedge clk);end
    uart_rx=1;repeat(DIVIDER+4000) @(negedge clk);
  endtask
  task command(input string text);
    for(integer i=0;i<text.len();i++) uart_byte(text[i]);uart_byte(8'h0d);
  endtask
  task settle;repeat(30000) @(negedge clk);endtask
  initial begin
    repeat(20) @(negedge clk);rst=0;wait(booted);settle();
    command("elf test");wait(tests==1);settle();
    if(hello!=2 || returned!=2 || faulted!=1 || timedout!=1 || illegal!=1) $fatal(1,"ELF diagnostic coverage");
    command("run /HELLO.ELF");wait(missing==1);settle();
    command("mount");wait(mounted==1);settle();
    command("run /BAD.ELF");wait(load_errors==1);settle();
    if(hello!=2 || returned!=2) $fatal(1,"Malformed ELF executed");
    command("run /HELLO.ELF alpha \"two words\"");wait(returned==3);settle();
    command("run /HELLO.ELF");wait(returned==4);settle();
    command("run /FAULT.ELF");wait(faulted==2);settle();
    command("run /LOOP.ELF");wait(dut.rv && dut.rpc>=32'h10000 && dut.rpc<32'h10020);repeat(200000) @(negedge clk);
    uart_byte(3);wait(cancelled==1);settle();
    command("run /HELLO.ELF retry");wait(returned==5);settle();
    command("ddrtest");wait(dma_ok==1);settle();
    command("uptime");wait(uptime==1);settle();
    if(!ticks || !heartbeat || !polls || dropped || timer_irqs<40 || yields<10 || app_retired<1000 || sd_reads<8 || sd_writes || illegal!=2 || call_count!=9 || return_count!=9 || call_active)
      $fatal(1,"ELF scheduler/IO coverage retired=%0d SD=%0d timer=%0d",app_retired,sd_reads,timer_irqs);
    $fclose(uart_file);
    $display("PTROCOS ELF SOC PASS style=%0d cycles=%0d app_retired=%0d SDreads=%0d timer=%0d yields=%0d restored=%0d hello BSS args exception timeout cancellation retry DMA",PC_STYLE,cycles,app_retired,sd_reads,timer_irqs,yields,return_count);
    $finish;
  end
endmodule
module tb_ptrocos_elf_alt;tb_ptrocos_elf #(.PC_STYLE(1)) test();endmodule
`default_nettype wire
