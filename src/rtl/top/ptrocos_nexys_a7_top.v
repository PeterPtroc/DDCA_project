`default_nettype none
module ptrocos_nexys_a7_top #(
    parameter CPU_PC_NEXT_STYLE=0,
    parameter UART_DIVIDER=868,
    parameter IMEM_HEX="build/hex/ptrocos_ddr2.hex"
) (
    input wire clk100, reset_n,
    input wire [15:0] sw,
    input wire [4:0] btn,
    output wire [15:0] led,
    input wire uart_rx,
    output wire uart_tx,
    input wire ps2_clk, ps2_data,
    input wire sd_miso, sd_cd_n,
    output wire sd_sck, sd_mosi, sd_cs_n, sd_reset,
    output wire [3:0] vga_red, vga_green, vga_blue,
    output wire vga_hsync, vga_vsync,
    output wire [7:0] pmod_ja,
    input wire jb1,
    output wire [7:0] seg_an,
    output wire [6:0] seg,
    output wire seg_dp, rgb0_r, rgb0_g, rgb0_b, rgb1_r, rgb1_g, rgb1_b,
    output wire [12:0] ddr2_addr,
    output wire [2:0] ddr2_ba,
    output wire ddr2_ras_n, ddr2_cas_n, ddr2_we_n,
    output wire [0:0] ddr2_ck_p, ddr2_ck_n, ddr2_cke, ddr2_cs_n, ddr2_odt,
    output wire [1:0] ddr2_dm,
    inout wire [15:0] ddr2_dq,
    inout wire [1:0] ddr2_dqs_p, ddr2_dqs_n
);
  wire cpu_clk, ui_clk, ui_sync_rst, mig_locked, calibrated, reference_clk200;
  wire clock_input, reference_raw, feedback_raw, feedback, reference_locked;
  // One input buffer and global 100 MHz clock feed both CPU and MIG. The MIG
  // preset uses NO_BUFFER system clock; a separate MMCM generates exactly
  // 200 MHz for IDELAYCTRL, independent of the DDR UI frequency.
  IBUF system_input(.I(clk100),.O(clock_input));
  BUFG cpu_clock(.I(clock_input),.O(cpu_clk));
  MMCME2_BASE #(.CLKIN1_PERIOD(10.0),.DIVCLK_DIVIDE(1),.CLKFBOUT_MULT_F(10.0),
      .CLKOUT0_DIVIDE_F(5.0),.STARTUP_WAIT("FALSE")) reference_mmcm (
      .CLKIN1(cpu_clk),.CLKFBIN(feedback),.RST(!reset_n),.PWRDWN(1'b0),
      .CLKFBOUT(feedback_raw),.CLKFBOUTB(),.CLKOUT0(reference_raw),.CLKOUT0B(),
      .CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),.CLKOUT3(),.CLKOUT3B(),
      .CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.LOCKED(reference_locked)
  );
  BUFG reference_feedback(.I(feedback_raw),.O(feedback));
  BUFG reference_clock(.I(reference_raw),.O(reference_clk200));
  wire pixel_clk,pixel_raw,pixel_feedback_raw,pixel_feedback,pixel_locked;
  // 100/5 * 31.5 / 25 = 25.2 MHz; VCO=630 MHz. 800*525 pixels = exactly 60 Hz.
  MMCME2_BASE #(.CLKIN1_PERIOD(10.0),.DIVCLK_DIVIDE(5),.CLKFBOUT_MULT_F(31.5),
      .CLKOUT0_DIVIDE_F(25.0),.STARTUP_WAIT("FALSE")) pixel_mmcm (
      .CLKIN1(cpu_clk),.CLKFBIN(pixel_feedback),.RST(!reset_n),.PWRDWN(1'b0),
      .CLKFBOUT(pixel_feedback_raw),.CLKFBOUTB(),.CLKOUT0(pixel_raw),.CLKOUT0B(),
      .CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),.CLKOUT3(),.CLKOUT3B(),
      .CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.LOCKED(pixel_locked)
  );
  BUFG pixel_feedback_buffer(.I(pixel_feedback_raw),.O(pixel_feedback));
  BUFG pixel_clock(.I(pixel_raw),.O(pixel_clk));
  wire reset_any=!reset_n || !reference_locked || !pixel_locked || !mig_locked || ui_sync_rst || !calibrated;
  (* ASYNC_REG="TRUE" *) reg [1:0] cpu_reset_sync=0, ui_reset_sync=0, pixel_reset_sync=0;
  always @(posedge cpu_clk or posedge reset_any) begin
    if(reset_any) cpu_reset_sync<=0;
    else cpu_reset_sync<={cpu_reset_sync[0],1'b1};
  end
  always @(posedge ui_clk or posedge reset_any) begin
    if(reset_any) ui_reset_sync<=0;
    else ui_reset_sync<={ui_reset_sync[0],1'b1};
  end
  always @(posedge pixel_clk or posedge reset_any) begin
    if(reset_any) pixel_reset_sync<=0;
    else pixel_reset_sync<={pixel_reset_sync[0],1'b1};
  end
  wire cpu_rst=!cpu_reset_sync[1], ui_rst=!ui_reset_sync[1], pixel_rst=!pixel_reset_sync[1];
  wire mv,mw,mr,me,tv,tw,tr,te;
  wire [31:0] ma,md,rd,ta,td,rr;
  wire [3:0] ms,ts;
  wire [26:0] awaddr,araddr;
  wire [7:0] awlen,arlen;
  wire [2:0] awsize,arsize;
  wire [1:0] awburst,arburst,bresp,rresp;
  wire awvalid,awready,wvalid,wready,wlast,bvalid,bready,arvalid,arready,rvalid,rready,rlast;
  wire [127:0] wdata,rdata;
  wire [15:0] wstrb;
  wire [26:0] cpu_araddr,scan_araddr;
  wire [7:0] cpu_arlen,scan_arlen;
  wire [2:0] cpu_arsize,scan_arsize;
  wire [1:0] cpu_arburst,scan_arburst,cpu_rresp,scan_rresp;
  wire cpu_arvalid,cpu_arready,scan_arvalid,scan_arready,cpu_rlast,cpu_rvalid,cpu_rready,scan_rlast,scan_rvalid,scan_rready;
  wire [127:0] cpu_rdata,scan_rdata;
  ptrocos_soc #(.CPU_PC_NEXT_STYLE(CPU_PC_NEXT_STYLE),.UART_DIVIDER(UART_DIVIDER),.IMEM_HEX(IMEM_HEX)) soc (
      .clk(cpu_clk),.rst(cpu_rst),.sw(sw),.btn(btn),.capture_in({7'd0,jb1}),
      .ui_clk(ui_clk),.ui_rst(ui_rst),
      .pixel_clk(pixel_clk),.pixel_rst(pixel_rst),.ps2_clk(ps2_clk),.ps2_data(ps2_data),
      .sd_miso(sd_miso),.sd_cd_n(sd_cd_n),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_cs_n(sd_cs_n),.sd_reset(sd_reset),
      .vga_red(vga_red),.vga_green(vga_green),.vga_blue(vga_blue),.vga_hsync(vga_hsync),.vga_vsync(vga_vsync),
      .uart_rx(uart_rx),.uart_tx(uart_tx),.led(led),.seg_an(seg_an),.seg(seg),.seg_dp(seg_dp),
      .rgb0_r(rgb0_r),.rgb0_g(rgb0_g),.rgb0_b(rgb0_b),.rgb1_r(rgb1_r),.rgb1_g(rgb1_g),.rgb1_b(rgb1_b),
      .memory_valid(mv),.memory_we(mw),.memory_addr(ma),.memory_wdata(md),.memory_wstrb(ms),
      .memory_ready(mr),.memory_rdata(rd),.memory_error(me),.trap_taken(),.trap_cause(),.firmware_result(),
      .scan_araddr(scan_araddr),.scan_arlen(scan_arlen),.scan_arsize(scan_arsize),.scan_arburst(scan_arburst),
      .scan_arvalid(scan_arvalid),.scan_arready(scan_arready),.scan_rdata(scan_rdata),.scan_rresp(scan_rresp),
      .scan_rlast(scan_rlast),.scan_rvalid(scan_rvalid),.scan_rready(scan_rready)
  );
  fixed_test_signals test_signals(.clk(cpu_clk),.rst(cpu_rst),.test_out(pmod_ja));
  word_bus_cdc ddr_cdc (
      .source_clk(cpu_clk),.source_rst(cpu_rst),.source_valid(mv),.source_we(mw),
      .source_addr(ma),.source_wdata(md),.source_wstrb(ms),.source_ready(mr),.source_rdata(rd),.source_error(me),
      .target_clk(ui_clk),.target_rst(ui_rst),.target_valid(tv),.target_we(tw),
      .target_addr(ta),.target_wdata(td),.target_wstrb(ts),.target_ready(tr),.target_rdata(rr),.target_error(te)
  );
  ddr2_axi_word_bridge ddr_bridge (
      .clk(ui_clk),.rst(ui_rst),.valid(tv),.we(tw),.addr(ta),.wdata(td),.wstrb(ts),.ready(tr),.rdata(rr),.error(te),
      .axi_awaddr(awaddr),.axi_awlen(awlen),.axi_awsize(awsize),.axi_awburst(awburst),.axi_awvalid(awvalid),.axi_awready(awready),
      .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wlast(wlast),.axi_wvalid(wvalid),.axi_wready(wready),
      .axi_bresp(bresp),.axi_bvalid(bvalid),.axi_bready(bready),
      .axi_araddr(cpu_araddr),.axi_arlen(cpu_arlen),.axi_arsize(cpu_arsize),.axi_arburst(cpu_arburst),.axi_arvalid(cpu_arvalid),.axi_arready(cpu_arready),
      .axi_rdata(cpu_rdata),.axi_rresp(cpu_rresp),.axi_rlast(cpu_rlast),.axi_rvalid(cpu_rvalid),.axi_rready(cpu_rready)
  );
  axi_read_arbiter read_bus (
      .clk(ui_clk),.rst(ui_rst),
      .cpu_araddr(cpu_araddr),.cpu_arlen(cpu_arlen),.cpu_arsize(cpu_arsize),.cpu_arburst(cpu_arburst),
      .cpu_arvalid(cpu_arvalid),.cpu_arready(cpu_arready),.cpu_rdata(cpu_rdata),.cpu_rresp(cpu_rresp),
      .cpu_rlast(cpu_rlast),.cpu_rvalid(cpu_rvalid),.cpu_rready(cpu_rready),
      .video_araddr(scan_araddr),.video_arlen(scan_arlen),.video_arsize(scan_arsize),.video_arburst(scan_arburst),
      .video_arvalid(scan_arvalid),.video_arready(scan_arready),.video_rdata(scan_rdata),.video_rresp(scan_rresp),
      .video_rlast(scan_rlast),.video_rvalid(scan_rvalid),.video_rready(scan_rready),
      .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
      .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready)
  );
  ptrocos_ddr2_mig memory (
      .ddr2_addr(ddr2_addr),.ddr2_ba(ddr2_ba),.ddr2_ras_n(ddr2_ras_n),.ddr2_cas_n(ddr2_cas_n),.ddr2_we_n(ddr2_we_n),
      .ddr2_ck_p(ddr2_ck_p),.ddr2_ck_n(ddr2_ck_n),.ddr2_cke(ddr2_cke),.ddr2_cs_n(ddr2_cs_n),.ddr2_odt(ddr2_odt),
      .ddr2_dm(ddr2_dm),.ddr2_dq(ddr2_dq),.ddr2_dqs_p(ddr2_dqs_p),.ddr2_dqs_n(ddr2_dqs_n),
      .sys_clk_i(cpu_clk),.clk_ref_i(reference_clk200),.sys_rst(reset_n && reference_locked),
      .ui_clk(ui_clk),.ui_clk_sync_rst(ui_sync_rst),
      .mmcm_locked(mig_locked),.init_calib_complete(calibrated),.aresetn(!ui_rst),
      .app_sr_req(1'b0),.app_ref_req(1'b0),.app_zq_req(1'b0),.app_sr_active(),.app_ref_ack(),.app_zq_ack(),
      .s_axi_awid(4'd0),.s_axi_awaddr(awaddr),.s_axi_awlen(awlen),.s_axi_awsize(awsize),.s_axi_awburst(awburst),
      .s_axi_awlock(1'b0),.s_axi_awcache(4'd0),.s_axi_awprot(3'd0),.s_axi_awqos(4'd0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
      .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wlast(wlast),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
      .s_axi_bid(),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
      .s_axi_arid(4'd0),.s_axi_araddr(araddr),.s_axi_arlen(arlen),.s_axi_arsize(arsize),.s_axi_arburst(arburst),
      .s_axi_arlock(1'b0),.s_axi_arcache(4'd0),.s_axi_arprot(3'd0),.s_axi_arqos(4'd0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
      .s_axi_rid(),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rlast(rlast),.s_axi_rvalid(rvalid),.s_axi_rready(rready)
  );
endmodule
`default_nettype wire
