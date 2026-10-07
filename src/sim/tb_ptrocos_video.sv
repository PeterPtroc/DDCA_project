`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_video #(parameter PC_STYLE=0);
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
  wire sd_miso,sd_sck,sd_mosi,sd_cs_n,sd_reset;
  reg attached=1,corrupt=0;wire [31:0] sd_commands,sd_reads,sd_writes,power_cycles;
  sd_spi_card_model #(.IMAGE("build/ptrocos_video/video-fat16.hex")) card (
      .sck(sd_sck),.mosi(sd_mosi),.cs_n(sd_cs_n),.power_off(sd_reset),.attached(attached),
      .corrupt_next_read(corrupt),.miso(sd_miso),.commands(sd_commands),.reads(sd_reads),
      .writes(sd_writes),.power_cycles(power_cycles));
  ptrocos_soc #(.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER),.IMEM_HEX("build/hex/ptrocos_video.hex")) dut (
      .ui_clk(ui_clk),.ui_rst(rst),.scan_araddr(va),.scan_arlen(vl),.scan_arsize(vsize),.scan_arburst(vb),
      .scan_arvalid(vv),.scan_arready(vr),.scan_rdata(vd),.scan_rresp(vp),
      .scan_rlast(vvlast),.scan_rvalid(vvvalid),.scan_rready(vvready),
      .vga_red(red),.vga_green(green),.vga_blue(blue),.vga_hsync(hsync),.vga_vsync(vsync),
      .clk(clk),.rst(rst),.sw(16'd0),.btn(5'd0),.uart_rx(uart_rx),.uart_tx(uart_tx),
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
  axi_graphics_memory #(.CAPACITY(8192)) memory (
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
  integer booted=0,mounts=0,started=0,finished=0,cancelled=0,formats=0,missing=0,texts=0;
  integer dma_ok=0,timer_irqs=0,yields=0,uptime_ok=0,io_errors=0;
  integer ticks,heartbeat,polls,dropped,last_frames,last_read,last_displayed,last_dropped,last_elapsed,last_late,last_rate,last_playing,last_fps;
  integer log_file;
  initial begin
    if(PC_STYLE==0) log_file=$fopen("build/ptrocos_video/uart.style0.log","w");
    else log_file=$fopen("build/ptrocos_video/uart.style1.log","w");
    if(!log_file) $fatal(1,"Video log open");
  end
  always @(posedge clk) if(!rst) begin
    cycles++;
    if(cycles>150000000) $fatal(1,"Video timeout PC=%x started=%0d finished=%0d SDreads=%0d",dut.ia,started,finished,sd_reads);
    if(trap) begin
      if(cause==11) yields++;else if(cause==32'h80000007) timer_irqs++;
      else $fatal(1,"Unexpected video trap %x",cause);
    end
    if(result[31:16]==16'hbad5) $fatal(1,"Video panic %x",result);
  end
  initial forever begin
    @(negedge uart_tx);#(DIVIDER*10/2);
    if(uart_tx!==0) $fatal(1,"Video UART start");
    for(bit_index=0;bit_index<8;bit_index++) begin #(DIVIDER*10);received[bit_index]=uart_tx;end
    #(DIVIDER*10);if(uart_tx!==1) $fatal(1,"Video UART stop");$fwrite(log_file,"%c",received);
    if(received==10) begin
      if(line=="PTROCOS SHELL READY") booted=1;
      if(line.substr(0,10)=="FAT mounted") mounts++;
      if(line.substr(0,7)=="PTV fps=") started++;
      if($sscanf(line,"PTV played fps=%d frames=%d read=%d displayed=%d dropped=%d elapsed_ms=%d max_late_ms=%d audio_rate=%d playing=%d",last_fps,last_frames,last_read,last_displayed,last_dropped,last_elapsed,last_late,last_rate,last_playing)==9) begin
        if(last_displayed+last_dropped!=last_frames || last_read!=last_frames || last_playing) $fatal(1,"Video accounting: %s",line);
        finished++;
      end
      if(line=="^C cancelled") cancelled++;
      if(line=="unsupported or malformed media file") formats++;
      if(line=="mount the SD card first") missing++;
      if(line=="gfx text mode") texts++;
      if(line=="DDR DMA PASS words=256 crc=0000f364") dma_ok++;
      if(line.substr(0,11)=="FatFs error=") io_errors++;
      if($sscanf(line,"ticks=%d heartbeat=%d io_polls=%d input_dropped=%d",ticks,heartbeat,polls,dropped)==4) uptime_ok++;
      $display("VIDEO UART style=%0d %s",PC_STYLE,line);line="";
    end else if(received!=13) line={line,received};
  end
  reg [127:0] expected[0:1919];reg [15:0] expected_pcm[0:2132];
  initial begin
    $readmemh("build/ptrocos_video/clip.0.words.hex",expected,0,239);
    $readmemh("build/ptrocos_video/clip.1.words.hex",expected,240,479);
    $readmemh("build/ptrocos_video/clip.2.words.hex",expected,480,719);
    $readmemh("build/ptrocos_video/clip.3.words.hex",expected,720,959);
    $readmemh("build/ptrocos_video/clip.4.words.hex",expected,960,1199);
    $readmemh("build/ptrocos_video/clip.5.words.hex",expected,1200,1439);
    $readmemh("build/ptrocos_video/clip.6.words.hex",expected,1440,1679);
    $readmemh("build/ptrocos_video/clip.7.words.hex",expected,1680,1919);
    $readmemh("build/ptrocos_video/clip.pcm.hex",expected_pcm);
  end
  integer checked_pixels=0,checked_samples=0,pcm_count=0,video_frames=0,physical_frames=0;
  reg [2:0] slot_frame[0:7];reg slot_valid[0:7];
  reg [31:0] old_base;reg old_enable=0;
  integer slot,index,shown_frame,source_row,source_bit;reg [127:0] word;
  reg expected_bit;
  reg [9:0] x1,y1,x2,y2,x3,y3;
  initial for(integer i=0;i<8;i++) begin slot_frame[i]=0;slot_valid[i]=0;end
  always @(posedge ui_clk) if(!rst) begin
    if(dut.graphics.active_enable && (dut.graphics.active_base!=old_base || !old_enable)) begin
      if(dut.graphics.active_base<32'h81200000 || dut.graphics.active_base>=32'h81208000 || !dut.graphics.active_mono)
        $fatal(1,"Video invalid active config %x",dut.graphics.active_base);
      slot=(dut.graphics.active_base-32'h81200000)/4096;
      word=memory.read_at(dut.graphics.active_base[26:0]);shown_frame=-1;
      for(integer f=0;f<8;f++) if(word===expected[f*240]) shown_frame=f;
      if(shown_frame<0) $fatal(1,"Unknown video bitmap first word");
      for(integer row=0;row<120;row++) for(integer beat=0;beat<2;beat++)
        if(memory.read_at(dut.graphics.active_base[26:0]+row*32+beat*16)!==expected[shown_frame*240+row*2+beat])
          $fatal(1,"Video DDR bitmap mismatch frame=%0d row=%0d beat=%0d",shown_frame,row,beat);
      slot_frame[slot]=shown_frame;slot_valid[slot]=1;video_frames++;
      $display("VIDEO SWAP style=%0d frame=%0d PCM=%0d base=%x",PC_STYLE,shown_frame,pcm_count,dut.graphics.active_base);
    end
    if(dut.graphics.active_enable && memory.got_aw && memory.got_w &&
        memory.saved_aw>=dut.graphics.active_base[26:0] && memory.saved_aw<dut.graphics.active_base[26:0]+3840)
      $fatal(1,"CPU overwrote active video front");
    old_base<=dut.graphics.active_base;old_enable<=dut.graphics.active_enable;
  end else begin old_base<=32'h81000000;old_enable<=0;end
  always @(posedge pclk) begin
    x1<=dut.graphics.scan_x;y1<=dut.graphics.scan_y;x2<=x1;y2<=y1;x3<=x2;y3<=y2;
    if(!rst) begin
      if(dut.graphics.scan_x==0 && dut.graphics.scan_y==0) physical_frames++;
      #1;
      if(dut.graphics.graphics_selected && x3<640 && y3<480) begin
        slot=(dut.graphics.active_base-32'h81200000)/4096;
        if(!slot_valid[slot]) $fatal(1,"Unpublished video slot");
        source_row=y3/4;source_bit=x3/4;
        word=expected[slot_frame[slot]*240+source_row*2+source_bit/128];expected_bit=word[source_bit%128];
        if({red,green,blue}!=={12{expected_bit}}) $fatal(1,"Video VGA mismatch frame=%0d x=%0d y=%0d",slot_frame[slot],x3,y3);
        checked_pixels++;
      end
    end
  end
  always @(posedge clk) if(!rst) begin
    #1;
    if(dut.audio.sample_valid) begin
      if(pcm_count>=2133 || dut.audio.pcm!==expected_pcm[pcm_count]) $fatal(1,"Video PCM mismatch count=%0d value=%x",pcm_count,dut.audio.pcm);
      pcm_count++;checked_samples++;
    end
    if(dut.audio.underruns || dut.audio.overflow || dut.audio.fault) $fatal(1,"Video audio fault queue=%0d",dut.audio.count);
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
  task frames(input integer count);integer before_frame;before_frame=physical_frames;wait(physical_frames>=before_frame+count);endtask
  initial begin
    repeat(20) @(negedge clk);rst=0;wait(booted);settle();
    command("play /CLIP.PTV");wait(missing==1);settle();
    command("mount");wait(mounts==1);settle();
    command("play /BAD.PTV");wait(formats==1);settle();
    pcm_count=0;command("play /CLIP.PTV");wait(finished==1);settle();
    if(pcm_count!=2133 || !dut.audio.done || last_rate!=8000 || last_frames!=8 || last_elapsed<266)
      $fatal(1,"Video normal audio accounting samples=%0d elapsed=%0d",pcm_count,last_elapsed);
    command("play /SILENT.PTV");wait(finished==2);settle();
    if(last_rate || last_frames!=5 || last_elapsed<166 || dut.audio.running) $fatal(1,"Silent video clock");
    pcm_count=0;command("play /CLIP.PTV");wait(started==3);wait(dut.audio.running && pcm_count>=32);
    uart_byte(3);wait(cancelled==1);settle();
    if(dut.audio.running || dut.audio.count) $fatal(1,"Video cancellation retained audio");
    // This cancellation interrupts a live SD read. The storage contract clears
    // initialization and mount, so retry must first prove the guard and remount.
    command("play /CLIP.PTV");wait(missing==2);settle();
    command("mount");wait(mounts==2);settle();
    pcm_count=0;command("play /CLIP.PTV");wait(finished==3);settle();
    if(pcm_count!=2133) $fatal(1,"Video retry PCM count");
    if(PC_STYLE==0) begin
      corrupt=1;command("play /CLIP.PTV");wait(io_errors==1);settle();corrupt=0;
      command("play /CLIP.PTV");wait(missing==3);settle();
      command("mount");wait(mounts==3);settle();
    end
    command("ddrtest");wait(dma_ok==1);settle();
    command("uptime");wait(uptime_ok==1);settle();
    if(!ticks || !heartbeat || !polls || dropped || !timer_irqs || yields<10) $fatal(1,"Video scheduler/input coverage");
    command("gfx off");wait(texts==1);frames(2);
    if(dut.graphics.graphics_selected || dut.graphics.read_errors || dut.graphics.underflow_snapshot ||
       checked_pixels<640*480*5 || checked_samples<4266 || sd_reads<20 || sd_writes || video_frames<8)
      $fatal(1,"Video coverage pixels=%0d samples=%0d swaps=%0d",checked_pixels,checked_samples,video_frames);
    $fclose(log_file);
    $display("PTROCOS VIDEO SOC PASS style=%0d cycles=%0d pixels=%0d samples=%0d SDreads=%0d swaps=%0d timer=%0d yields=%0d real-PTV silent sample-clock cancellation retry CRC DMA",PC_STYLE,cycles,checked_pixels,checked_samples,sd_reads,video_frames,timer_irqs,yields);
    $finish;
  end
endmodule
module tb_ptrocos_video_alt;tb_ptrocos_video #(.PC_STYLE(1)) test();endmodule
`default_nettype wire
