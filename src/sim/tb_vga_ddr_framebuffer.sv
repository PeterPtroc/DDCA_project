`timescale 1ns/1ps
`default_nettype none
module tb_vga_ddr_framebuffer #(parameter FULL=0,MONO=0);
  localparam WIDTH=FULL ? 640 : 32,HEIGHT=FULL ? 480 : 12;
  localparam H_TOTAL=FULL ? 800 : 40,V_TOTAL=FULL ? 525 : 16;
  localparam STRIDE=MONO ? 48 : WIDTH*2+16;
  localparam MIN_STRIDE=MONO ? 32 : WIDTH*2;
  localparam BASE_A=MONO ? 32'h81200ff0 : 32'h81000ff0;
  localparam BASE_B=MONO ? 32'h81301000 : 32'h81101000;
  reg clk=0,ui_clk=0,pixel_clk=0,rst=1;
  always #5 clk=~clk;always #6.1535 ui_clk=~ui_clk;always #19.84127 pixel_clk=~pixel_clk;
  reg valid=0,we=0;reg [31:0] addr=0,wdata=0;reg [3:0] strb=15;
  wire ready;wire [31:0] rdata;
  wire [26:0] va,ca,ma;wire [7:0] vl,ml;wire [2:0] vs,ms;wire [1:0] vb,mb;
  wire vv,vr,cv,cr,mv,mr,vrlast,vrvalid,crlast,crvalid,mrlast,mrvalid;
  wire [127:0] vrd,crd,mrd;wire [1:0] vresp,cresp,mresp;
  wire vrr,crr,mrr;
  wire [3:0] red,green,blue;wire selected;wire [9:0] sx,sy;
  reg stall=0;reg [2:0] fault=0;
  integer writes,reads,bursts;
  vga_ddr_framebuffer #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.H_TOTAL(H_TOTAL),.V_TOTAL(V_TOTAL)) dut (
      .clk(clk),.rst(rst),.ui_clk(ui_clk),.ui_rst(rst),.pixel_clk(pixel_clk),.pixel_rst(rst),
      .reg_valid(valid),.reg_we(we),.reg_addr(addr),.reg_wdata(wdata),.reg_wstrb(strb),.reg_ready(ready),.reg_rdata(rdata),
      .axi_araddr(va),.axi_arlen(vl),.axi_arsize(vs),.axi_arburst(vb),.axi_arvalid(vv),.axi_arready(vr),
      .axi_rdata(vrd),.axi_rresp(vresp),.axi_rlast(vrlast),.axi_rvalid(vrvalid),.axi_rready(vrr),
      .red(red),.green(green),.blue(blue),.graphics_selected(selected),.scan_x(sx),.scan_y(sy)
  );
  reg cpu_valid=0,cpu_ready=1;reg [26:0] cpu_addr=27'h0100200;
  assign ca=cpu_addr;assign cv=cpu_valid;assign crr=cpu_ready;
  axi_read_arbiter arbiter (
      .clk(ui_clk),.rst(rst),.cpu_araddr(ca),.cpu_arlen(8'd0),.cpu_arsize(3'd4),.cpu_arburst(2'd1),
      .cpu_arvalid(cv),.cpu_arready(cr),.cpu_rdata(crd),.cpu_rresp(cresp),.cpu_rlast(crlast),.cpu_rvalid(crvalid),.cpu_rready(crr),
      .video_araddr(va),.video_arlen(vl),.video_arsize(vs),.video_arburst(vb),.video_arvalid(vv),.video_arready(vr),
      .video_rdata(vrd),.video_rresp(vresp),.video_rlast(vrlast),.video_rvalid(vrvalid),.video_rready(vrr),
      .araddr(ma),.arlen(ml),.arsize(ms),.arburst(mb),.arvalid(mv),.arready(mr),
      .rdata(mrd),.rresp(mresp),.rlast(mrlast),.rvalid(mrvalid),.rready(mrr)
  );
  axi_graphics_memory #(.CAPACITY(1024),.INITIAL_PATTERN(1)) memory (
      .clk(ui_clk),.rst(rst),.stall_reads(stall),.fault_mode(fault),
      .awaddr(27'd0),.awlen(8'd0),.awsize(3'd4),.awburst(2'd1),.awvalid(1'b0),
      .wvalid(1'b0),.wlast(1'b1),.wdata(128'd0),.wstrb(16'd0),.bready(1'b1),.awready(),.wready(),.bvalid(),.bresp(),
      .araddr(ma),.arlen(ml),.arsize(ms),.arburst(mb),.arvalid(mv),.arready(mr),
      .rready(mrr),.rdata(mrd),.rresp(mresp),.rlast(mrlast),.rvalid(mrvalid),.write_count(writes),.read_count(reads),.burst_count(bursts)
  );
  reg [11:0] expected_a[0:WIDTH*HEIGHT-1],expected_b[0:WIDTH*HEIGHT-1];
  reg [11:0] expected_rgb[0:WIDTH*HEIGHT-1];
  reg [127:0] mono_a[0:239],mono_b[0:239];
  reg color_mode=MONO;
  initial begin
    if(MONO) begin
      $readmemh("build/ptrocos_video/mono.0.rgb.hex",expected_a);$readmemh("build/ptrocos_video/mono.1.rgb.hex",expected_b);
      $readmemh("build/ptrocos_video/mono.0.words.hex",mono_a);$readmemh("build/ptrocos_video/mono.1.words.hex",mono_b);
      $readmemh("build/ptrocos_graphics/full.0.rgb.hex",expected_rgb);
    end
    else if(FULL) begin $readmemh("build/ptrocos_graphics/full.0.rgb.hex",expected_a);$readmemh("build/ptrocos_graphics/full.1.rgb.hex",expected_b);end
    else begin $readmemh("build/ptrocos_graphics/small.0.rgb.hex",expected_a);$readmemh("build/ptrocos_graphics/small.1.rgb.hex",expected_b);end
  end
  task prime_mono;
    integer slot,offset;reg [26:0] address;
    if(MONO) for(integer row=0;row<120;row++) for(integer beat=0;beat<2;beat++) begin
      address=BASE_A[26:0]+row*48+beat*16;slot=memory.lookup(address[26:4]);
      memory.occupied[slot]=1;memory.tags[slot]=address[26:4];memory.data[slot]=mono_a[row*2+beat];
      address=BASE_B[26:0]+row*48+beat*16;slot=memory.lookup(address[26:4]);
      memory.occupied[slot]=1;memory.tags[slot]=address[26:4];memory.data[slot]=mono_b[row*2+beat];
    end
  endtask
  reg checking=0;integer front=0,checked_pixels=0,cycles=0,cpu_reads=0,transactions=0,physical_frames=0;
  reg [9:0] x1,y1,x2,y2,x3,y3;
  reg [11:0] expected_pixel;
  reg row_matches,row_black;
  integer black_lines=0;
  reg [31:0] old_base,old_swaps;
  reg old_mono=0;
  always @(posedge ui_clk) if(!rst) begin
    if(dut.active_base!=old_base || dut.swaps!=old_swaps || dut.active_mono!=old_mono)
      if(sy<HEIGHT) $fatal(1,"Front buffer changed during visible pixels");
    old_base<=dut.active_base;old_swaps<=dut.swaps;old_mono<=dut.active_mono;
    if(crvalid && vrvalid) $fatal(1,"Read response delivered to both owners");
  end else begin old_base<=32'h81000000;old_swaps<=0;old_mono<=0;end
  reg held=0;reg [39:0] held_ar;
  always @(posedge ui_clk) begin
    if(rst) held<=0;
    else begin
      if(held && (!mv || {ma,ml,ms,mb}!==held_ar)) $fatal(1,"AR payload changed under backpressure");
      held<=mv && !mr;if(mv && !mr) held_ar<={ma,ml,ms,mb};
    end
  end
  always @(posedge pixel_clk) begin
    x1<=sx;y1<=sy;x2<=x1;y2<=y1;x3<=x2;y3<=y2;
    if(!rst) begin
      if(sx==0 && sy==0) physical_frames++;
      #1;
      if(selected && x3<WIDTH && y3<HEIGHT) begin
        if(x3==0) begin row_matches=1;row_black=1;end
        expected_pixel=MONO && !color_mode ? expected_rgb[y3*WIDTH+x3] : front ? expected_b[y3*WIDTH+x3] : expected_a[y3*WIDTH+x3];
        if({red,green,blue}!==expected_pixel) row_matches=0;
        if({red,green,blue}!==12'd0) row_black=0;
        if(x3==WIDTH-1) begin
          if(!row_matches && !row_black) $fatal(1,"Underrun/error displayed a partial or stale line");
          if(row_black) black_lines++;
        end
      end
      if(checking && selected && x3<WIDTH && y3<HEIGHT) begin
        expected_pixel=MONO && !color_mode ? expected_rgb[y3*WIDTH+x3] : front ? expected_b[y3*WIDTH+x3] : expected_a[y3*WIDTH+x3];
        if({red,green,blue}!==expected_pixel) $fatal(1,"RGB mismatch full=%0d frame=%0d x=%0d y=%0d got=%x expected=%x",FULL,physical_frames,x3,y3,{red,green,blue},expected_pixel);
        checked_pixels++;
      end
      if((x3>=WIDTH || y3>=HEIGHT) && {red,green,blue}!==12'd0) $fatal(1,"Color outside visible area");
    end
  end
  always @(posedge clk) if(!rst) begin cycles++;if(cycles>(MONO ? 120000000 : FULL ? 20000000 : 1000000)) $fatal(1,"Graphics timeout");end
  task access(input bit write,input [7:0] offset,input [31:0] value,input [3:0] strobes,output reg [31:0] response);
    @(negedge clk);valid=1;we=write;addr=32'h4000e000+offset;wdata=value;strb=strobes;
    while(!ready) @(negedge clk);
    response=rdata;@(negedge clk);valid=0;we=0;transactions++;
    repeat(3) @(negedge clk);
  endtask
  reg [31:0] response;
  integer saved_underflows,saved_errors;
  task put(input [7:0] offset,input [31:0] value);access(1,offset,value,15,response);endtask
  task get(input [7:0] offset);access(0,offset,0,15,response);endtask
  task frames(input integer count);
    integer before_frame;
    before_frame=physical_frames;wait(physical_frames>=before_frame+count);
  endtask
  task wait_swap(input [31:0] base);
    get(12);while(response[1]) get(12);
    get(16);if(response!==base) $fatal(1,"Wrong committed framebuffer base");
  endtask
  initial begin
    repeat(20) @(negedge clk);rst=0;prime_mono();
    get(44);if(response!==((HEIGHT<<16)|WIDTH)) $fatal(1,"Size register");
    get(48);if(response!==16'h0565) $fatal(1,"Pixel format register");
    if(MONO) begin
      access(1,52,1,1,response);get(52);if(response) $fatal(1,"Partial format write accepted");
      put(52,2);put(8,3);get(12);if(!response[2] || response[1]) $fatal(1,"Unsupported format accepted");
      put(8,4);put(52,1);
    end
    put(0,32'h81000000);access(1,0,32'hffff0ff0,3,response);get(0);
    if(response!==32'h81000ff0) $fatal(1,"Base byte strobes");
    put(4,MIN_STRIDE-16);put(8,3);get(12);
    if(!response[2] || response[1]) $fatal(1,"Short stride accepted");
    put(8,4);put(4,STRIDE+1);put(8,3);get(12);
    if(!response[2] || response[1]) $fatal(1,"Unaligned stride accepted");
    put(8,4);put(4,STRIDE);put(0,32'h87fffff0);put(8,3);get(12);
    if(!response[2] || response[1]) $fatal(1,"Framebuffer past DDR end accepted");
    put(8,4);put(4,32'hfffffff0);put(0,32'h80000000);put(8,3);get(12);
    if(!response[2] || response[1]) $fatal(1,"64-bit address overflow accepted");
    put(8,4);
    put(0,32'h80000001);put(8,3);get(12);if(!response[2] || response[1]) $fatal(1,"Invalid base accepted");
    put(8,4);put(0,BASE_A);put(4,STRIDE);put(8,3);
    if(MONO) put(52,0);
    wait_swap(BASE_A);
    if(MONO) begin get(56);if(response!=1) $fatal(1,"Format was not captured at submit");put(52,1);end
    frames(2);checking=1;frames(2);checking=0;
    get(32);if(response) $fatal(1,"Unexpected ordinary scanout underrun %0d",response);
    put(0,BASE_B);put(8,3);wait_swap(BASE_B);front=1;
    frames(2);checking=1;frames(2);checking=0;
    if(!FULL || MONO) begin
      for(integer mode=1;mode<=3;mode++) begin
        fault=mode;frames(3);get(40);if(!response) $fatal(1,"AXI error not reported mode=%0d",mode);
        fault=0;frames(3);checking=1;frames(2);checking=0;
      end
      stall=1;frames(3);put(0,BASE_A);put(8,3);
      get(12);if(!response[1]) $fatal(1,"Swap did not remain pending during stalled AXI");
      put(8,3);get(12);if(!response[2]) $fatal(1,"Busy commit was not rejected");
      stall=0;wait_swap(BASE_A);front=0;
      frames(3);get(32);if(!response) $fatal(1,"Starvation did not produce underrun count");
      checking=1;frames(2);checking=0;
      put(8,4);get(12);if(response[4:2]) $fatal(1,"Sticky error clear failed");
    end
    put(8,1);wait_swap(front ? BASE_B : BASE_A);frames(2);
    if(selected || writes || checked_pixels<WIDTH*HEIGHT*3 || cpu_reads<20 || ((!FULL || MONO) && black_lines<HEIGHT))
      $fatal(1,"Graphics coverage pixels=%0d cpu=%0d black-lines=%0d",checked_pixels,cpu_reads,black_lines);
    saved_underflows=dut.underflow_snapshot;saved_errors=dut.read_errors;
    if(!FULL || MONO) begin
      put(0,BASE_A);put(8,3);wait_swap(BASE_A);
      wait(memory.reading && memory.read_total>1);@(negedge ui_clk);stall=1;
      repeat(5) @(negedge clk);rst=1;repeat(25) @(negedge clk);stall=0;rst=0;front=0;prime_mono();
      get(12);if(response) $fatal(1,"Reset retained graphics state");
      get(28);if(response) $fatal(1,"Reset retained swap count");
      get(32);if(response) $fatal(1,"Reset retained underrun count");
      if(MONO) put(52,1);
      put(0,BASE_A);put(4,STRIDE);put(8,3);wait_swap(BASE_A);
      frames(2);checking=1;frames(2);checking=0;
      put(8,1);wait_swap(BASE_A);frames(2);
      get(32);if(response || selected) $fatal(1,"Reset recovery did not restore healthy scanout");
    end
    if(MONO) begin
      put(52,0);put(0,32'h81000ff0);put(4,WIDTH*2+16);put(8,3);wait_swap(32'h81000ff0);color_mode=0;
      frames(2);checking=1;frames(2);checking=0;
      get(56);if(response) $fatal(1,"RGB format not restored");
      put(52,1);put(0,BASE_B);put(4,STRIDE);put(8,3);wait_swap(BASE_B);front=1;color_mode=1;
      frames(2);checking=1;frames(2);checking=0;
      put(8,1);wait_swap(BASE_B);frames(2);
    end
    $display("DDR FRAMEBUFFER UNIT PASS full=%0d pixels=%0d cpu-reads=%0d bursts=%0d beats=%0d swaps=%0d underflows=%0d errors=%0d black-lines=%0d transactions=%0d RGB565 full-address 4K splits fair-read CDC safe-swap reset-recovery",
        FULL,checked_pixels,cpu_reads,bursts,reads,dut.swaps,saved_underflows,saved_errors,black_lines,transactions);
    $finish;
  end
  // Continuous CPU reads contend with video, with independent R-channel pauses.
  integer cpu_cycle=0;reg outstanding=0;
  initial begin
    wait(!rst);
    forever begin
      @(negedge ui_clk);cpu_cycle++;cpu_ready=cpu_cycle%5!=3;
      if(rst) begin cpu_valid=0;outstanding=0;cpu_addr=27'h0100200;end
      else if(!outstanding && !cpu_valid) cpu_valid=1;
      @(posedge ui_clk);
      if(!rst && cpu_valid && cr) begin cpu_valid<=0;outstanding=1;end
      if(!rst && crvalid && cpu_ready) begin
        if(cresp || !crlast || crd!==memory.read_at(cpu_addr)) $fatal(1,"CPU read corrupted by graphics arbiter");
        outstanding=0;cpu_addr=cpu_addr+16;cpu_reads++;
      end
    end
  end
endmodule
module tb_vga_ddr_framebuffer_full;tb_vga_ddr_framebuffer #(.FULL(1)) test();endmodule
module tb_vga_ddr_mono;tb_vga_ddr_framebuffer #(.FULL(1),.MONO(1)) test();endmodule
`default_nettype wire
