`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_media #(parameter PC_STYLE=0);
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
  sd_spi_card_model #(.IMAGE("build/ptrocos_media/media-fat16.hex")) card (
      .sck(sd_sck),.mosi(sd_mosi),.cs_n(sd_cs_n),.power_off(sd_reset),.attached(attached),
      .corrupt_next_read(corrupt),.miso(sd_miso),.commands(sd_commands),.reads(sd_reads),
      .writes(sd_writes),.power_cycles(power_cycles));
  ptrocos_soc #(.CPU_PC_NEXT_STYLE(PC_STYLE),.UART_DIVIDER(DIVIDER),.IMEM_HEX("build/hex/ptrocos_media.hex")) dut (
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
  integer booted=0,mounts=0,bmp_started=0,displayed=0,wav_started=0,wav_done=0;
  integer cancelled=0,format_errors=0,io_errors=0,missing_mount=0,dma_ok=0,text_mode=0,audio_ok=0;
  integer ticks=0,heartbeat=0,io=0,dropped=0,uptime_ok=0,timer_irqs=0,yields=0;
  integer log_file;
  always @(posedge clk) if(!rst) begin
    cycles<=cycles+1;
    if(cycles>160000000) $fatal(1,"Media timeout pc=%x displays=%0d WAV=%0d reads=%0d",dut.ia,displayed,wav_done,sd_reads);
    if(trap) begin
      if(cause==11) yields++;else if(cause==32'h80000007) timer_irqs++;
      else $fatal(1,"Unexpected media trap %x",cause);
    end
    if(result[31:16]==16'hbad5) $fatal(1,"Media panic %x",result);
  end
  initial begin
    log_file=$fopen(PC_STYLE==0 ? "build/ptrocos_media/uart.style0.log" : "build/ptrocos_media/uart.style1.log","w");
    if(!log_file) $fatal(1,"Media log open");
  end
  initial forever begin
    @(negedge uart_tx);#(DIVIDER*10/2);
    if(uart_tx!==0) $fatal(1,"UART start");
    for(bit_index=0;bit_index<8;bit_index++) begin #(DIVIDER*10);received[bit_index]=uart_tx;end
    #(DIVIDER*10);if(uart_tx!==1) $fatal(1,"UART stop");$fwrite(log_file,"%c",received);
    if(received==10) begin
      if(line=="PTROCOS SHELL READY") booted=1;
      if(line.substr(0,10)=="FAT mounted") mounts++;
      if(line.substr(0,9)=="BMP width=") bmp_started++;
      if(line=="BMP displayed") displayed++;
      if(line.substr(0,8)=="WAV rate=") wav_started++;
      if(line.substr(0,17)=="WAV played frames=") wav_done++;
      if(line=="^C cancelled") cancelled++;
      if(line=="unsupported or malformed media file") format_errors++;
      if(line.substr(0,11)=="FatFs error=") io_errors++;
      if(line=="mount the SD card first") missing_mount++;
      if(line=="DDR DMA PASS words=256 crc=0000f364") dma_ok++;
      if(line=="gfx text mode") text_mode++;
      if(line=="AUDIO PASS rate=8000 samples=256 underruns=0") audio_ok++;
      if($sscanf(line,"ticks=%d heartbeat=%d io_polls=%d input_dropped=%d",ticks,heartbeat,io,dropped)==4) uptime_ok++;
      $display("MEDIA UART style=%0d %s",PC_STYLE,line);line="";
    end else if(received!=13) line={line,received};
  end
  reg [11:0] expected_image[0:307199],expected_top[0:307199];
  reg [15:0] expected_sound[0:4800],expected_short[0:536];
  initial begin
    $readmemh("build/ptrocos_media/image.rgb.hex",expected_image);
    $readmemh("build/ptrocos_media/top.rgb.hex",expected_top);
    $readmemh("build/ptrocos_media/sound.pcm.hex",expected_sound);
    $readmemh("build/ptrocos_media/short.pcm.hex",expected_short);
  end
  integer pcm_kind=0,pcm_count=0,checked_samples=0,checked_pixels=0,frames_seen=0,concurrent_reads=0;
  reg [15:0] expected_sample;reg [11:0] expected_pixel;
  always @(posedge clk) if(!rst) begin
    #1;
    if(dut.audio.sample_valid) begin
      if(pcm_kind==1 && pcm_count<4801) expected_sample=expected_sound[pcm_count];
      else if(pcm_kind==2 && pcm_count<537) expected_sample=expected_short[pcm_count];
      else if(pcm_kind==3 && pcm_count<256) expected_sample=pcm_count*257;
      else $fatal(1,"Unexpected audio sample kind=%0d count=%0d",pcm_kind,pcm_count);
      if(dut.audio.pcm!==expected_sample) $fatal(1,"Media PCM mismatch index=%0d got=%x expected=%x",pcm_count,dut.audio.pcm,expected_sample);
      pcm_count++;checked_samples++;
    end
    if(dut.audio.underruns || dut.audio.overflow || dut.audio.fault) $fatal(1,"Media audio FIFO/rate fault count=%0d",dut.audio.count);
  end
  reg [9:0] x1,y1,x2,y2,x3,y3;
  always @(posedge pclk) begin
    x1<=dut.graphics.scan_x;y1<=dut.graphics.scan_y;x2<=x1;y2<=y1;x3<=x2;y3<=y2;
    if(!rst) begin
      if(dut.graphics.scan_x==0 && dut.graphics.scan_y==0) frames_seen++;
      #1;
      if(dut.graphics.graphics_selected && x3<640 && y3<480) begin
        if(dut.graphics.active_base==32'h81100000) expected_pixel=expected_image[y3*640+x3];
        else expected_pixel=expected_top[y3*640+x3];
        if({red,green,blue}!==expected_pixel) $fatal(1,"Media VGA pixel mismatch x=%0d y=%0d got=%x expected=%x",x3,y3,{red,green,blue},expected_pixel);
        checked_pixels++;
      end
    end
  end
  always @(posedge ui_clk) if(!rst && cv && cr && dut.graphics.active_enable) concurrent_reads++;
  task uart_byte(input byte value);
    @(negedge clk);uart_rx=0;repeat(DIVIDER) @(negedge clk);
    for(integer i=0;i<8;i++) begin uart_rx=value[i];repeat(DIVIDER) @(negedge clk);end
    uart_rx=1;repeat(DIVIDER+4000) @(negedge clk);
  endtask
  task command(input string text);
    for(integer i=0;i<text.len();i++) uart_byte(text[i]);uart_byte(8'h0d);
  endtask
  task settle;repeat(30000) @(negedge clk);endtask
  task frames(input integer count);integer before_frame;before_frame=frames_seen;wait(frames_seen>=before_frame+count);endtask
  integer before_writes,before_cancel,before_reads;
  initial begin
    repeat(20) @(negedge clk);rst=0;wait(booted);settle();
    command("bmp /IMAGE.BMP");wait(missing_mount==1);settle();
    command("mount");wait(mounts==1);settle();
    command("bmp /BAD.BMP");wait(format_errors==1);settle();
    command("wav /BAD.WAV");wait(format_errors==2);settle();
    if(dut.graphics.swaps || dut.audio.played) $fatal(1,"Rejected format changed output");
    command("bmp /IMAGE.BMP");wait(displayed==1);frames(3);settle();
    if(dut.graphics.active_base!=32'h81100000 || dut.graphics.swaps!=1) $fatal(1,"BMP first flip");
    pcm_kind=1;pcm_count=0;command("wav /SOUND.WAV");wait(wav_done==1);settle();
    if(pcm_count!=4801 || dut.audio.played!=4801 || !dut.audio.done) $fatal(1,"WAV drain accounting");
    pcm_kind=2;pcm_count=0;command("wav /SHORT.WAV");wait(wav_done==2);settle();
    if(pcm_count!=537) $fatal(1,"8-bit mono conversion count");
    before_writes=write_count;command("bmp /TOP.BMP");wait(bmp_started==2);
    wait(write_count>=before_writes+640);uart_byte(3);wait(cancelled==1);settle();
    if(dut.graphics.swaps!=1 || dut.graphics.active_base!=32'h81100000) $fatal(1,"Cancelled BMP changed front");
    // Cancellation during drawing keeps the volume mounted and immediately retryable.
    command("bmp /TOP.BMP");wait(displayed==2);frames(2);settle();
    if(dut.graphics.swaps!=2 || dut.graphics.active_base!=32'h81000000) $fatal(1,"Top-down BMP flip");
    pcm_kind=1;pcm_count=0;command("wav /SOUND.WAV");wait(wav_started==3);
    // Current stream, not the previous file's retained completion counter.
    wait(dut.audio.running && dut.audio.draining && dut.audio.played>=32);
    uart_byte(3);wait(cancelled==2);settle();
    if(dut.audio.running || dut.audio.count || wav_done!=2) $fatal(1,"Cancelled WAV retained audio");
    if(PC_STYLE==0) begin
      // Remove a card during active audio; queued output must stop on the I/O error.
      pcm_count=0;command("wav /SOUND.WAV");wait(wav_started==4);
      wait(dut.audio.running && dut.audio.played>=32 && !dut.audio.draining);attached=0;
      wait(io_errors==1);settle();
      if(dut.audio.running || dut.audio.count) $fatal(1,"Removed SD kept playing");
      command("wav /SHORT.WAV");wait(missing_mount==2);settle();attached=1;
      command("mount");wait(mounts==2);settle();
      corrupt=1;command("bmp /IMAGE.BMP");wait(io_errors==2);settle();corrupt=0;
      if(dut.graphics.swaps!=2) $fatal(1,"CRC failure published a BMP");
      command("mount");wait(mounts==3);settle();
    end
    pcm_kind=3;pcm_count=0;command("audio test");wait(audio_ok==1);settle();
    if(pcm_count!=256 || dut.audio.running || !dut.audio.done) $fatal(1,"Diagnostic audio");
    command("ddrtest");wait(dma_ok==1);settle();
    command("uptime");wait(uptime_ok==1);settle();
    if(result!==32'h600d7005 || dropped || heartbeat<10 || io<100 || yields<100 || timer_irqs<100)
      $fatal(1,"Media scheduler/input health result=%x dropped=%0d",result,dropped);
    if(dut.graphics.underflow_snapshot || dut.graphics.read_errors) $fatal(1,"Media graphics health");
    command("gfx off");wait(text_mode==1);frames(2);
    if(checked_pixels<1228800 || checked_samples<5594 || concurrent_reads<256 || sd_reads<40 || sd_writes)
      $fatal(1,"Media coverage pixels=%0d PCM=%0d reads=%0d",checked_pixels,checked_samples,sd_reads);
    $fclose(log_file);
    $display("PTROCOS MEDIA SOC PASS style=%0d cycles=%0d pixels=%0d samples=%0d SDreads=%0d CPUreads-during-scan=%0d timer=%0d yields=%0d fragmented-BMP WAV cancel drain recovery DDR-DMA",PC_STYLE,cycles,checked_pixels,checked_samples,sd_reads,concurrent_reads,timer_irqs,yields);
    $finish;
  end
endmodule
module tb_ptrocos_media_alt;tb_ptrocos_media #(.PC_STYLE(1)) test();endmodule
`default_nettype wire
