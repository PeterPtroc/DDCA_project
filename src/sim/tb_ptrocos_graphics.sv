`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_graphics #(parameter PC_STYLE=0);
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
  integer write_count,read_count,burst_count;
  wire [26:0] ca,va,ra;wire [7:0] cl,vl,rl;wire [2:0] csize,vsize,rsize;
  wire [1:0] cb,vb,rb,cp,vp,rp;wire cv,cr,vv,vr,rv,rrdy;
  wire [127:0] cd,vd,rdata_bus;wire cvlast,cvvalid,cvready,vvlast,vvvalid,vvready,rlast_bus,rvalid_bus;
  wire [3:0] red,green,blue;wire hsync,vsync;
  integer cycles=0;
  integer uart_file,bit_index;
  reg [7:0] received;
  string line="";
  ptrocos_soc #(.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER),.IMEM_HEX("build/hex/ptrocos_graphics.hex")) dut (
      .ui_clk(ui_clk),.ui_rst(rst),.scan_araddr(va),.scan_arlen(vl),.scan_arsize(vsize),.scan_arburst(vb),
      .scan_arvalid(vv),.scan_arready(vr),.scan_rdata(vd),.scan_rresp(vp),
      .scan_rlast(vvlast),.scan_rvalid(vvvalid),.scan_rready(vvready),
      .vga_red(red),.vga_green(green),.vga_blue(blue),.vga_hsync(hsync),.vga_vsync(vsync),
      .clk(clk),.rst(rst),.sw(16'd0),.btn(5'd0),.uart_rx(uart_rx),.uart_tx(uart_tx),
      .sd_miso(1'b1),.sd_cd_n(1'b1),.sd_sck(),.sd_mosi(),.sd_cs_n(),.sd_reset(),
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
      .axi_araddr(ca),.axi_arlen(cl),.axi_arsize(csize),.axi_arburst(cb),.axi_arvalid(cv),.axi_arready(cr),
      .axi_rdata(cd),.axi_rresp(cp),.axi_rlast(cvlast),.axi_rvalid(cvvalid),.axi_rready(cvready)
  );
  axi_read_arbiter arbiter (
      .clk(ui_clk),.rst(rst),.cpu_araddr(ca),.cpu_arlen(cl),.cpu_arsize(csize),.cpu_arburst(cb),
      .cpu_arvalid(cv),.cpu_arready(cr),.cpu_rdata(cd),.cpu_rresp(cp),.cpu_rlast(cvlast),.cpu_rvalid(cvvalid),.cpu_rready(cvready),
      .video_araddr(va),.video_arlen(vl),.video_arsize(vsize),.video_arburst(vb),
      .video_arvalid(vv),.video_arready(vr),.video_rdata(vd),.video_rresp(vp),.video_rlast(vvlast),.video_rvalid(vvvalid),.video_rready(vvready),
      .araddr(ra),.arlen(rl),.arsize(rsize),.arburst(rb),.arvalid(rv),.arready(rrdy),
      .rdata(rdata_bus),.rresp(rp),.rlast(rlast_bus),.rvalid(rvalid_bus),.rready(rready)
  );
  axi_graphics_memory memory (
      .clk(ui_clk),.rst(rst),.stall_reads(1'b0),.fault_mode(3'd0),
      .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),
      .wvalid(wvalid),.wlast(wlast),.bready(bready),.wdata(wdata),.wstrb(wstrb),
      .awready(awready),.wready(wready),.bvalid(bvalid),.bresp(bresp),
      .araddr(ra),.arlen(rl),.arsize(rsize),.arburst(rb),.arvalid(rv),.arready(rrdy),
      .rready(rready),.rdata(rdata_bus),.rresp(rp),.rlast(rlast_bus),.rvalid(rvalid_bus),
      .write_count(write_count),.read_count(read_count),.burst_count(burst_count)
  );
  always #5 clk=~clk;
  always #6.1535 ui_clk=~ui_clk;
  always #19.84127 pclk=~pclk;
  reg booted=0,dma_ok=0,uptime_ok=0,text_mode=0,usage_ok=0;
  integer drawing=0,displayed=0,cancelled=0;
  integer yields=0,mtime_irqs=0,ticks_report=0,heartbeat_report=0,io_report=0,dropped_report=0;
  integer info_count=0,status_report=0,front_report=0,frames_report=0,swaps_report=0,under_report=0,beats_report=0,errors_report=0;
  integer log_file;
  always @(posedge clk) if(!rst) begin
    cycles<=cycles+1;
    if(cycles>80000000) $fatal(1,"GRAPHICS timeout pc=%x result=%x drawn=%0d displayed=%0d",dut.ia,result,drawing,displayed);
    if(trap) begin
      if(cause==11) yields++;
      else if(cause==32'h80000007) mtime_irqs++;
      else $fatal(1,"Unexpected graphics shell trap %x",cause);
    end
    if(result[31:16]==16'hbad5) $fatal(1,"Graphics shell panic %x",result);
  end
  initial begin
    log_file=$fopen(PC_STYLE==0 ? "build/ptrocos_graphics/uart.style0.log" : "build/ptrocos_graphics/uart.style1.log","w");
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
      if(line=="gfx drawing; Ctrl+C cancels") drawing++;
      if(line=="gfx pattern=0 displayed" || line=="gfx pattern=1 displayed") displayed++;
      if(line=="^C cancelled") cancelled++;
      if(line=="DDR DMA PASS words=256 crc=0000f364") dma_ok=1;
      if(line=="gfx text mode") text_mode=1;
      if(line=="usage: gfx info | pattern 0..1 | off | clear") usage_ok=1;
      if($sscanf(line,"ticks=%d heartbeat=%d io_polls=%d input_dropped=%d",ticks_report,heartbeat_report,io_report,dropped_report)==4) uptime_ok=1;
      if($sscanf(line,"gfx 640x480 RGB565 stride=1280 status=%d front=%d frames=%d swaps=%d underruns=%d beats=%d errors=%d",
          status_report,front_report,frames_report,swaps_report,under_report,beats_report,errors_report)==7) info_count++;
      if(line.len()<190) $display("GRAPHICS UART style=%0d %s",PC_STYLE,line);
      line="";
    end else if(received!=13) line={line,received};
  end
  reg [11:0] expected0[0:307199],expected1[0:307199];
  initial begin
    $readmemh("build/ptrocos_graphics/shell.0.rgb.hex",expected0);
    $readmemh("build/ptrocos_graphics/shell.1.rgb.hex",expected1);
  end
  reg [9:0] x1,y1,x2,y2,x3,y3;
  reg [11:0] expected_pixel;
  integer checked0=0,checked1=0,video_reads=0,cpu_reads=0,concurrent_writes=0,frames_seen=0;
  integer progress_writes=0;
  reg [31:0] previous_base=32'h81000000,previous_swaps=0;
  always @(posedge ui_clk) if(!rst) begin
    if(dut.graphics.active_base!=previous_base || dut.graphics.swaps!=previous_swaps)
      if(dut.graphics.scan_y<480) $fatal(1,"Software flip tore a visible frame");
    previous_base<=dut.graphics.active_base;previous_swaps<=dut.graphics.swaps;
    if(vv && vr) video_reads++;
    if(cv && cr) cpu_reads++;
    if(awvalid && awready && dut.graphics.active_enable) concurrent_writes++;
    if(write_count/38400>progress_writes) begin
      progress_writes=write_count/38400;
      $display("GRAPHICS DRAW PROGRESS style=%0d cycles=%0d AXIwrite=%0d swaps=%0d",PC_STYLE,cycles,write_count,dut.graphics.swaps);
    end
  end
  always @(posedge pclk) begin
    x1<=dut.graphics.scan_x;y1<=dut.graphics.scan_y;x2<=x1;y2<=y1;x3<=x2;y3<=y2;
    if(!rst) begin
      if(dut.graphics.scan_x==0 && dut.graphics.scan_y==0) frames_seen++;
      #1;
      if(dut.graphics.graphics_selected && x3<640 && y3<480) begin
        if(dut.graphics.active_base==32'h81100000) begin expected_pixel=expected0[y3*640+x3];checked0++;end
        else if(dut.graphics.active_base==32'h81000000) begin expected_pixel=expected1[y3*640+x3];checked1++;end
        else $fatal(1,"Unexpected software framebuffer base");
        if({red,green,blue}!==expected_pixel) $fatal(1,"SoC RGB mismatch base=%x x=%0d y=%0d got=%x expected=%x",dut.graphics.active_base,x3,y3,{red,green,blue},expected_pixel);
      end
      if(dut.graphics.graphics_selected && (x3>=640 || y3>=480) && {red,green,blue}!==12'd0)
        $fatal(1,"Graphics blanking mismatch");
      if(hsync!==(x3>=656 && x3<752 ? 1'b0 : 1'b1) || vsync!==(y3>=490 && y3<492 ? 1'b0 : 1'b1))
        if(cycles>100) $fatal(1,"Text/graphics sync lost alignment");
    end
  end
  task uart_byte(input byte value);
    @(negedge clk);uart_rx=0;repeat(DIVIDER) @(negedge clk);
    for(integer i=0;i<8;i++) begin uart_rx=value[i];repeat(DIVIDER) @(negedge clk);end
    uart_rx=1;repeat(DIVIDER) @(negedge clk);
    // 服务任务有意按实际的 1 kHz 系统节拍频率运行。
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
  task command(input string value);uart_text(value);uart_byte(8'h0d);endtask
  task frames(input integer count);
    integer before_frame;before_frame=frames_seen;wait(frames_seen>=before_frame+count);
  endtask
  integer before_writes,before_displayed,before_cancelled,before_info;
  bit vga_cancelled;
  initial begin
    repeat(20) @(negedge clk);rst=0;wait(booted);repeat(20000) @(negedge clk);
    command("gfx pattern 2");wait(usage_ok);repeat(20000) @(negedge clk);
    if(write_count || dut.graphics.swaps) $fatal(1,"Invalid graphics command touched DDR");
    command("gfx info");wait(info_count==1);repeat(20000) @(negedge clk);
    if(status_report || swaps_report || errors_report || under_report) $fatal(1,"Initial graphics state");
    command("gfx pattern 0");wait(drawing==1);
    // 另一个 TTY 等待同一个图形互斥锁，随后取消该等待。
    scan(8'h34);scan(8'h2b);scan(8'h22);scan(8'h29);scan(8'h44);scan(8'h2b);scan(8'h2b);scan(8'h5a);
    repeat(200000) @(negedge clk);scan(8'h14);scan(8'h21);scan(8'hf0);scan(8'h14);
    wait(displayed==1);frames(3);repeat(20000) @(negedge clk);
    if(dut.graphics.active_base!==32'h81100000 || dut.graphics.swaps!=1) $fatal(1,"Initial software flip");
    vga_cancelled=0;
    for(integer cell_index=0;cell_index<2388;cell_index++) begin
      if(dut.text_display.cells[cell_index][7:0]=="^" && dut.text_display.cells[cell_index+1][7:0]=="C" &&
         dut.text_display.cells[cell_index+3][7:0]=="c" && dut.text_display.cells[cell_index+11][7:0]=="d") vga_cancelled=1;
    end
    if(!vga_cancelled) $fatal(1,"VGA session did not cancel the mutex wait");
    before_writes=write_count;command("gfx pattern 1");wait(drawing==2);
    wait(write_count>=before_writes+640);uart_byte(3);wait(cancelled==1);repeat(30000) @(negedge clk);
    if(dut.graphics.active_base!==32'h81100000 || dut.graphics.swaps!=1 || displayed!=1)
      $fatal(1,"Cancelled drawing changed front buffer");
    command("gfx pattern 1");wait(displayed==2);frames(3);repeat(20000) @(negedge clk);
    if(dut.graphics.active_base!==32'h81000000 || dut.graphics.swaps!=2) $fatal(1,"Second software flip");
    command("ddrtest");wait(dma_ok);repeat(20000) @(negedge clk);
    command("gfx info");wait(info_count==2);repeat(20000) @(negedge clk);
    if(status_report!=1 || under_report || errors_report || swaps_report!=2 || beats_report<38400)
      $fatal(1,"Graphics hardware counters status=%0d underruns=%0d errors=%0d swaps=%0d",status_report,under_report,errors_report,swaps_report);
    command("uptime");wait(uptime_ok);repeat(20000) @(negedge clk);
    if(result!==32'h600d7005 || yields<100 || mtime_irqs<100 || heartbeat_report<10 || io_report<100 || dropped_report)
      $fatal(1,"Graphics scheduler/input coverage result=%x",result);
    command("gfx off");wait(text_mode);frames(2);
    if(dut.graphics.graphics_selected || dut.graphics.active_enable) $fatal(1,"Text mode did not return");
    if(checked0<614400 || checked1<614400 || video_reads<4000 || cpu_reads<256 || concurrent_writes<153600)
      $fatal(1,"Graphics coverage pixels0=%0d pixels1=%0d scan-reads=%0d cpu-reads=%0d writes=%0d",checked0,checked1,video_reads,cpu_reads,concurrent_writes);
    if(dut.keyboard.frame_count || dut.keyboard.timeout_total || dut.keyboard.overflow_count) $fatal(1,"PS2 simulation error");
    $fclose(log_file);
    $display("PTROCOS GRAPHICS SOC PASS style=%0d cycles=%0d yields=%0d timer=%0d pixels0=%0d pixels1=%0d CPUreads=%0d video-bursts=%0d concurrent-writes=%0d AXIwrite=%0d AXIread=%0d two-TTY mutex cancel safe-swap DDR-DMA text-return",
        PC_STYLE,cycles,yields,mtime_irqs,checked0,checked1,cpu_reads,video_reads,concurrent_writes,write_count,read_count);
    $finish;
  end

endmodule
module tb_ptrocos_graphics_alt;tb_ptrocos_graphics #(.PC_STYLE(1)) test();endmodule
`default_nettype wire
