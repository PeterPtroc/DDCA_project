`default_nettype none
module soc_top #(
    parameter IMEM_HEX = "build/hex/freertos.hex",
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
    output wire rgb1_b
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
  wire machine_timer_irq, machine_software_irq;
  wire clint_sel = (da[31:16] == 16'h0200);
  reg [1:0] read_region;
  reg [31:0] peripheral_rdata;

  rv32_core #(.CPU_PC_NEXT_STYLE(CPU_PC_NEXT_STYLE)) cpu (
      .clk(clk), .rst(rst), .imem_addr(ia), .imem_rdata(id),
      .dmem_valid(dv), .dmem_we(dwe), .dmem_wstrb(dstrb),
      .dmem_addr(da), .dmem_wdata(dw), .dmem_rdata(dr),
      .machine_timer_irq(machine_timer_irq),
      .machine_software_irq(machine_software_irq),
      .retire_valid(rv), .retire_pc(rpc),
      .retire_insn(ri), .retire_rd_we(rwe), .retire_rd(rr), .retire_rd_data(rd),
      .trap_taken(), .trap_cause(),
      .event_stall_load(es), .event_fwd_ex_count(ef), .event_fwd_wb_count(wf),
      .event_flush(fl), .event_branch(br), .event_branch_taken(bt),
      .event_custom_crc(crc)
  );
  imem #(.HEX_FILE(IMEM_HEX)) im (
      .clk(clk), .addr(ia), .rdata(id),
      .data_addr(da), .data_rdata(imem_data_rdata)
  );
  dmem dm (
      .clk(clk), .rst(rst), .we(dv && dwe), .wstrb(dstrb),
      .addr(da), .wdata(dw),
      .rdata(dmem_rdata)
  );
  clint machine_timer (
      .clk(clk), .rst(rst), .valid(dv && clint_sel), .we(dwe),
      .wstrb(dstrb), .addr(da), .wdata(dw), .rdata(clint_r),
      .machine_timer_irq(machine_timer_irq),
      .machine_software_irq(machine_software_irq)
  );
  mmio_decoder #(
      .BUTTON_DEBOUNCE_BITS(BUTTON_DEBOUNCE_BITS),
      .UART_DIVIDER(UART_DIVIDER),
      .EDGE_MIN_TIMEOUT_TICKS(EDGE_MIN_TIMEOUT_TICKS),
      .EDGE_INITIAL_TIMEOUT_TICKS(EDGE_INITIAL_TIMEOUT_TICKS),
      .LIVE_AUTO_TIMEOUT_SAMPLES(LIVE_AUTO_TIMEOUT_SAMPLES)
  ) bus (
      .clk(clk), .rst(rst), .valid(dv), .we(dwe), .addr(da), .wdata(dw),
      .sw(sw), .btn(btn), .capture_in(capture_in), .uart_rx_i(uart_rx),
      .retire(rv), .stall(es), .fwd_ex(ef),
      .fwd_wb(wf), .flush(fl), .branch(br), .branch_taken(bt), .crc(crc),
      .rdata(mmio_r), .led(led), .test_result(test_result), .uart_tx(uart_tx),
      .capture_armed(),
      .capture_triggered(), .capture_done(), .seg_an(seg_an),
      .seg(seg), .seg_dp(seg_dp), .rgb0_r(rgb0_r), .rgb0_g(rgb0_g),
      .rgb0_b(rgb0_b), .rgb1_r(rgb1_r), .rgb1_g(rgb1_g), .rgb1_b(rgb1_b)
  );
  // Remember the registered EX/MEM request region while the BRAM ports perform their
  // synchronous read.  MMIO/CLINT data is captured at the request edge too,
  // so every load presents a stable response for the complete following
  // cycle regardless of the next instruction's address.
  always @(posedge clk) begin
    if (rst) begin
      read_region <= 2'd0;
      peripheral_rdata <= 32'd0;
    end else if (dv && !dwe) begin
      if (da[31:16] == 16'h0000)
        read_region <= 2'd1;
      else if (clint_sel || da[31:28] == 4'h4) begin
        read_region <= 2'd2;
        peripheral_rdata <= clint_sel ? clint_r : mmio_r;
      end else
        read_region <= 2'd0;
    end
  end

  // ROM occupies 0x0000_0000..0x0000_ffff on the data side as read-only.
  // This is used for .rodata and as the load image for initialized .data.
  assign dr = (read_region == 2'd1) ? imem_data_rdata :
              (read_region == 2'd2) ? peripheral_rdata : dmem_rdata;
endmodule
`default_nettype wire
