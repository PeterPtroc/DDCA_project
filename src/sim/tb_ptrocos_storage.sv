`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_storage #(parameter PC_STYLE=0);
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
  wire sd_miso,sd_sck,sd_mosi,sd_cs_n,sd_reset;
  reg attached=1,corrupt=0;
  wire [31:0] sd_commands,sd_reads,sd_writes,power_cycles;
  sd_spi_card_model #(.HIGH_CAPACITY(PC_STYLE==0),.VERSION2(PC_STYLE==0),
      .IMAGE(PC_STYLE==0 ? "build/ptrocos_storage/fat16.hex" : "build/ptrocos_storage/fat12.hex")) card (
      .sck(sd_sck),.mosi(sd_mosi),.cs_n(sd_cs_n),.power_off(sd_reset),.attached(attached),
      .corrupt_next_read(corrupt),.miso(sd_miso),.commands(sd_commands),.reads(sd_reads),.writes(sd_writes),.power_cycles(power_cycles)
  );
  ptrocos_soc #(.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER),.IMEM_HEX("build/hex/ptrocos_storage.hex")) dut (
      .ui_clk(ui_clk),.ui_rst(rst),.scan_araddr(),.scan_arlen(),.scan_arsize(),.scan_arburst(),
      .scan_arvalid(),.scan_arready(1'b0),.scan_rdata(128'd0),.scan_rresp(2'd0),
      .scan_rlast(1'b0),.scan_rvalid(1'b0),.scan_rready(),
      .clk(clk),.rst(rst),.sw(16'd0),.btn(5'd0),.capture_in(8'd0),.uart_rx(uart_rx),.uart_tx(uart_tx),
      .sd_miso(sd_miso),.sd_cd_n(!attached),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_cs_n(sd_cs_n),.sd_reset(sd_reset),
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
  reg booted=0,cancelled=0,uptime_ok=0;
  integer mounts=0,file_passes=0,nested_passes=0,errors=0,missing_mount=0,unmounts=0;
  integer yields=0,mtime_irqs=0,ticks_report=0,heartbeat_report=0,io_report=0,dropped_report=0;
  integer log_file,previous_reads,previous_passes,previous_errors;
  always @(posedge clk) if(!rst) begin
    cycles<=cycles+1;
    if(cycles>60000000) $fatal(1,"STORAGE timeout pc=%x result=%x mounts=%0d passes=%0d commands=%0d reads=%0d",dut.ia,result,mounts,file_passes,sd_commands,sd_reads);
    if(trap) begin
      if(cause==11) yields++;
      else if(cause==32'h80000007) mtime_irqs++;
      else $fatal(1,"Unexpected storage trap %x",cause);
    end
    if(result[31:16]==16'hbad5) $fatal(1,"Storage panic %x",result);
  end
  initial begin
    log_file=$fopen(PC_STYLE==0 ? "build/ptrocos_storage/uart.style0.log" : "build/ptrocos_storage/uart.style1.log","w");
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
      if(line=="FILE PASS bytes=1100 crc=0000c0fe") file_passes++;
      if(line=="FILE PASS bytes=256 crc=0000de6c") nested_passes++;
      if(line=="^C cancelled") cancelled=1;
      if(line=="FAT unmounted") unmounts++;
      if(line=="mount the SD card first") missing_mount++;
      if(line=="FatFs error=1 SD=crc" || line=="FatFs error=1 SD=no-card" || line=="FatFs error=3 SD=no-card") errors++;
      if((PC_STYLE==0 && line=="FAT mounted type=2 sectors=32768") ||
         (PC_STYLE==1 && line=="FAT mounted type=1 sectors=32768")) mounts++;
      if($sscanf(line,"ticks=%d heartbeat=%d io_polls=%d input_dropped=%d",ticks_report,heartbeat_report,io_report,dropped_report)==4) uptime_ok=1;
      if(line.len()<180) $display("STORAGE UART style=%0d %s",PC_STYLE,line);
      line="";
    end else if(received!=13) line={line,received};
  end
  task uart_byte(input byte value);
    @(negedge clk);uart_rx=0;repeat(DIVIDER) @(negedge clk);
    for(integer i=0;i<8;i++) begin uart_rx=value[i];repeat(DIVIDER) @(negedge clk);end
    uart_rx=1;repeat(DIVIDER) @(negedge clk);repeat(4000) @(negedge clk);
  endtask
  task uart_text(input string value);
    for(integer i=0;i<value.len();i++) uart_byte(value[i]);
  endtask
  initial begin
    repeat(20) @(negedge clk);rst=0;wait(booted);
    uart_text("fscheck /HELLO.TXT\n");wait(missing_mount==1);
    uart_text("mount\n");wait(mounts==1);
    uart_text("fscheck /HELLO.TXT\n");wait(file_passes==1);
    uart_text("fscheck /SUBDIR/NESTED.BIN\n");wait(nested_passes==1);
    uart_text("sdinfo\n");repeat(100000) @(negedge clk);
    if(PC_STYLE==0) begin
      corrupt=1;uart_text("fscheck /HELLO.TXT\n");wait(errors==1);corrupt=0;
      uart_text("fscheck /HELLO.TXT\n");wait(missing_mount==2);
      uart_text("mount\n");wait(mounts==2);
      uart_text("fscheck /HELLO.TXT\n");wait(file_passes==2);
      previous_reads=sd_reads;uart_text("fscheck /HELLO.TXT\n");wait(sd_reads>previous_reads);
      attached=0;wait(errors==2);repeat(20) @(negedge clk);attached=1;
      uart_text("mount\n");wait(mounts==3);
      uart_text("fscheck /HELLO.TXT\n");wait(file_passes==3);
      previous_reads=sd_reads;uart_text("fscheck /HELLO.TXT\n");wait(sd_reads>previous_reads);
      uart_byte(3);wait(cancelled);
      uart_text("mount\n");wait(mounts==4);
      uart_text("fscheck /HELLO.TXT\n");wait(file_passes==4);
    end
    uart_text("umount\n");wait(unmounts==1);
    uart_text("mem\n");uart_text("tasks\n");uart_text("uptime\n");wait(uptime_ok);
    repeat(20000) @(negedge clk);
    if(result!==32'h600d7005 || yields<10 || mtime_irqs<20 || heartbeat_report<3 || io_report<20 || dropped_report)
      $fatal(1,"Storage scheduler coverage hb=%0d timer=%0d result=%x",heartbeat_report,mtime_irqs,result);
    if(sd_writes || sd_reads<5 || sd_commands<15 || !sd_cs_n || sd_sck || dut.sd.fault)
      $fatal(1,"SD model/state coverage commands=%0d reads=%0d writes=%0d",sd_commands,sd_reads,sd_writes);
    $fclose(log_file);
    $display("PTROCOS STORAGE SOC PASS style=%0d cycles=%0d yields=%0d timer=%0d heartbeat=%0d io=%0d commands=%0d reads=%0d mounts=%0d file-passes=%0d errors=%0d delayed-MISO CRC FAT scheduler",
      PC_STYLE,cycles,yields,mtime_irqs,heartbeat_report,io_report,sd_commands,sd_reads,mounts,file_passes,errors);
    $finish;
  end
endmodule
module tb_ptrocos_storage_alt;tb_ptrocos_storage #(.PC_STYLE(1)) test();endmodule
`default_nettype wire
