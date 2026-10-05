`default_nettype none
// Experimental SoC; the original soc_top and its CPU remain frozen.
module ptrocos_soc #(
    parameter IMEM_HEX = "build/hex/ptrocos_ddr2.hex",
    parameter BUTTON_DEBOUNCE_BITS = 18,
    parameter UART_DIVIDER = 868,
    parameter EDGE_MIN_TIMEOUT_TICKS = 10000000,
    parameter EDGE_INITIAL_TIMEOUT_TICKS = 100000000,
    parameter LIVE_AUTO_TIMEOUT_SAMPLES = 1024,
    parameter CPU_PC_NEXT_STYLE = 0
) (
    input wire clk,
    input wire rst,
    input wire [15:0] sw,
    input wire [4:0] btn,
    input wire [7:0] capture_in,
    input wire uart_rx,
    input wire pixel_clk, pixel_rst, ps2_clk, ps2_data,
    output wire [3:0] vga_red, vga_green, vga_blue,
    output wire vga_hsync, vga_vsync,
    output wire [15:0] led,
    output wire uart_tx,
    output wire [7:0] seg_an,
    output wire [6:0] seg,
    output wire seg_dp,
    output wire rgb0_r,
    output wire rgb0_g,
    output wire rgb0_b,
    output wire rgb1_r,
    output wire rgb1_g,
    output wire rgb1_b,
    output wire memory_valid, memory_we,
    output wire [31:0] memory_addr, memory_wdata,
    output wire [3:0] memory_wstrb,
    input wire memory_ready,
    input wire [31:0] memory_rdata,
    input wire memory_error,
    output wire trap_taken,
    output wire [31:0] trap_cause,
    output wire [31:0] firmware_result
);
  wire [31:0] ia, id, da, dw, dr, dmem_rdata, imem_data_rdata;
  wire dv, dwe;
  wire [3:0] dstrb;
  wire rv, rwe;
  wire [31:0] rpc, ri, rd;
  wire [4:0] rr;
  wire es;
  wire [1:0] ef, wf;
  wire fl, br, bt, crc;
  wire [31:0] mmio_r;
  wire [31:0] clint_r;
  wire [31:0] test_result;
  wire machine_timer_irq_raw, machine_software_irq;
  reg machine_timer_irq;
  // Register the 64-bit CLINT comparison before CPU interrupt/flush logic.
  // MTIP asserts/deasserts one cycle later; CLINT itself stays unchanged.
  always @(posedge clk) begin
    if(rst) machine_timer_irq<=0;
    else machine_timer_irq<=machine_timer_irq_raw;
  end
  wire clint_sel = (da[31:16] == 16'h0200);
  // Route all of 0x8... to the DDR bridge so accesses beyond 128 MiB fault.
  wire ddr_sel = da[31:28] == 4'h8;
  wire dma_sel = da[31:12] == 20'h4000a;
  wire vga_reg_sel = da[31:12] == 20'h4000b;
  wire keyboard_sel = da[31:12] == 20'h4000c;
  wire vga_cell_sel = da[31:14] == 18'h10004;
  wire rom_sel = da[31:16] == 16'h0000;
  wire ram_sel = da[31:16] == 16'h1000;
  wire mmio_sel = da[31:28] == 4'h4;
  wire [31:0] cpu_ddr_rdata, dma_mmio_rdata, dma_data;
  wire cpu_ddr_ready, cpu_ddr_error, dma_valid, dma_we, dma_ready, dma_error;
  wire [31:0] dma_addr, dma_wdata;
  wire [3:0] dma_wstrb;
  wire [31:0] vga_cell_rdata, vga_reg_rdata, keyboard_rdata;
  wire vga_reg_ready;
  wire data_ready = ddr_sel ? cpu_ddr_ready : vga_reg_sel ? vga_reg_ready : 1'b1;
  wire data_error = ddr_sel ? cpu_ddr_error :
      (!rom_sel && !ram_sel && !clint_sel && !mmio_sel) || (rom_sel && dwe);
  reg [2:0] read_region;
  reg [31:0] peripheral_rdata;

  rv32im_mem_core #(.CPU_PC_NEXT_STYLE(CPU_PC_NEXT_STYLE)) cpu (
      .clk(clk), .rst(rst), .imem_addr(ia), .imem_rdata(id),
      .dmem_valid(dv), .dmem_we(dwe), .dmem_wstrb(dstrb),
      .dmem_addr(da), .dmem_wdata(dw), .dmem_rdata(dr),
      .dmem_ready(data_ready), .dmem_error(data_error),
      .machine_timer_irq(machine_timer_irq),
      .machine_software_irq(machine_software_irq),
      .retire_valid(rv), .retire_pc(rpc),
      .retire_insn(ri), .retire_rd_we(rwe), .retire_rd(rr), .retire_rd_data(rd),
      .trap_taken(trap_taken), .trap_cause(trap_cause),
      .event_stall_load(es), .event_fwd_ex_count(ef), .event_fwd_wb_count(wf),
      .event_flush(fl), .event_branch(br), .event_branch_taken(bt),
      .event_custom_crc(crc)
  );
  imem #(.HEX_FILE(IMEM_HEX)) im (
      .clk(clk), .addr(ia), .rdata(id),
      .data_addr(da), .data_rdata(imem_data_rdata)
  );
  dmem dm (
      .clk(clk), .rst(rst), .we(dv && dwe && ram_sel), .wstrb(dstrb),
      .addr(da), .wdata(dw),
      .rdata(dmem_rdata)
  );
  clint machine_timer (
      .clk(clk), .rst(rst), .valid(dv && clint_sel), .we(dwe),
      .wstrb(dstrb), .addr(da), .wdata(dw), .rdata(clint_r),
      .machine_timer_irq(machine_timer_irq_raw),
      .machine_software_irq(machine_software_irq)
  );
  mmio_decoder #(
      .BUTTON_DEBOUNCE_BITS(BUTTON_DEBOUNCE_BITS),
      .UART_DIVIDER(UART_DIVIDER),
      .EDGE_MIN_TIMEOUT_TICKS(EDGE_MIN_TIMEOUT_TICKS),
      .EDGE_INITIAL_TIMEOUT_TICKS(EDGE_INITIAL_TIMEOUT_TICKS),
      .LIVE_AUTO_TIMEOUT_SAMPLES(LIVE_AUTO_TIMEOUT_SAMPLES)
  ) bus (
      .clk(clk), .rst(rst), .valid(dv && !ddr_sel && !dma_sel && !vga_reg_sel && !vga_cell_sel && !keyboard_sel), .we(dwe), .addr(da), .wdata(dw),
      .sw(sw), .btn(btn), .capture_in(capture_in), .uart_rx_i(uart_rx),
      .retire(rv), .stall(es), .fwd_ex(ef),
      .fwd_wb(wf), .flush(fl), .branch(br), .branch_taken(bt), .crc(crc),
      .rdata(mmio_r), .led(led), .test_result(test_result), .uart_tx(uart_tx),
      .capture_armed(),
      .capture_triggered(), .capture_done(), .seg_an(seg_an),
      .seg(seg), .seg_dp(seg_dp), .rgb0_r(rgb0_r), .rgb0_g(rgb0_g),
      .rgb0_b(rgb0_b), .rgb1_r(rgb1_r), .rgb1_g(rgb1_g), .rgb1_b(rgb1_b)
  );
  assign firmware_result = test_result;
  vga_text text_display (
      .clk(clk),.rst(rst),.pixel_clk(pixel_clk),.pixel_rst(pixel_rst),
      .cell_valid(dv && vga_cell_sel),.cell_we(dwe),.cell_addr(da[13:2]),
      .cell_wdata(dw),.cell_wstrb(dstrb),.cell_rdata(vga_cell_rdata),
      .reg_valid(dv && vga_reg_sel),.reg_we(dwe),.reg_addr(da),.reg_wdata(dw),
      .reg_wstrb(dstrb),.reg_ready(vga_reg_ready),.reg_rdata(vga_reg_rdata),
      .red(vga_red),.green(vga_green),.blue(vga_blue),.hsync(vga_hsync),.vsync(vga_vsync)
  );
  ps2_keyboard keyboard (
      .clk(clk),.rst(rst),.ps2_clk(ps2_clk),.ps2_data(ps2_data),
      .valid(dv && keyboard_sel),.we(dwe),.addr(da),.wdata(dw),.wstrb(dstrb),
      .rdata(keyboard_rdata),.irq()
  );
  dma_copy dma (
      .clk(clk), .rst(rst), .mmio_valid(dv && dma_sel), .mmio_we(dwe),
      .mmio_addr(da), .mmio_wdata(dw), .mmio_wstrb(dstrb), .mmio_rdata(dma_mmio_rdata),
      .mem_valid(dma_valid), .mem_we(dma_we), .mem_addr(dma_addr), .mem_wdata(dma_wdata),
      .mem_wstrb(dma_wstrb), .mem_ready(dma_ready), .mem_rdata(dma_data), .mem_error(dma_error)
  );
  word_bus_arbiter memory_bus (
      .clk(clk), .rst(rst), .cpu_valid(dv && ddr_sel), .cpu_we(dwe),
      .cpu_addr(da), .cpu_wdata(dw), .cpu_wstrb(dstrb),
      .cpu_ready(cpu_ddr_ready), .cpu_rdata(cpu_ddr_rdata), .cpu_error(cpu_ddr_error),
      .dma_valid(dma_valid), .dma_we(dma_we), .dma_addr(dma_addr), .dma_wdata(dma_wdata),
      .dma_wstrb(dma_wstrb), .dma_ready(dma_ready), .dma_rdata(dma_data), .dma_error(dma_error),
      .valid(memory_valid), .we(memory_we), .addr(memory_addr), .wdata(memory_wdata),
      .wstrb(memory_wstrb), .ready(memory_ready), .rdata(memory_rdata), .error(memory_error)
  );
  // Remember the registered EX/MEM request region while the BRAM ports perform their
  // synchronous read.  MMIO/CLINT data is captured at the request edge too,
  // so every load presents a stable response for the complete following
  // cycle regardless of the next instruction's address.
  always @(posedge clk) begin
    if (rst) begin
      read_region <= 2'd0;
      peripheral_rdata <= 32'd0;
    end else if (dv && data_ready && !dwe) begin
      if (ddr_sel)
        read_region <= 3'd3;
      else if (dma_sel)
        read_region <= 3'd4;
      else if (vga_cell_sel)
        read_region <= 3'd5;
      else if (vga_reg_sel)
        read_region <= 3'd6;
      else if (da[31:16] == 16'h0000)
        read_region <= 2'd1;
      else if (clint_sel || da[31:28] == 4'h4) begin
        read_region <= 2'd2;
        peripheral_rdata <= clint_sel ? clint_r : keyboard_sel ? keyboard_rdata : mmio_r;
      end else
        read_region <= 2'd0;
    end
  end

  // ROM occupies 0x0000_0000..0x0000_ffff on the data side as read-only.
  // This is used for .rodata and as the load image for initialized .data.
  assign dr = (read_region == 2'd1) ? imem_data_rdata :
              (read_region == 2'd2) ? peripheral_rdata :
              (read_region == 3'd3) ? cpu_ddr_rdata :
              (read_region == 3'd4) ? dma_mmio_rdata :
              (read_region == 3'd5) ? vga_cell_rdata :
              (read_region == 3'd6) ? vga_reg_rdata : dmem_rdata;
endmodule
`default_nettype wire
