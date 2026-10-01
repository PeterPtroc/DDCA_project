`default_nettype none
module soc_top #(
    parameter IMEM_HEX = "build/hex/analyzer.hex"
) (
    input wire clk,
    input wire rst,
    input wire [15:0] sw,
    input wire [4:0] btn,
    input wire [7:0] capture_in,
    input wire uart_rx,
    output wire [15:0] led,
    output wire uart_tx,
    output wire pwm_out,
    output wire [7:0] pattern_out,
    output wire pattern_enabled,
    output wire [31:0] test_result,
    output wire capture_done,
    output wire [7:0] seg_an,
    output wire [6:0] seg,
    output wire seg_dp,
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire vga_hs,
    output wire vga_vs
);
  wire [31:0] ia, id, da, dw, dr, dmem_rdata;
  wire dv, dwe;
  wire rv, rwe;
  wire [31:0] rpc, ri, rd;
  wire [4:0] rr;
  wire es;
  wire [1:0] ef, wf;
  wire fl, br, bt, crc;
  wire [31:0] mmio_r;
  wire ca, ct;
  wire [7:0] cs;
  wire [11:0] display_index;
  wire [7:0] display_sample;

  rv32_core cpu (
      .clk(clk), .rst(rst), .imem_addr(ia), .imem_rdata(id),
      .dmem_valid(dv), .dmem_we(dwe), .dmem_addr(da), .dmem_wdata(dw),
      .dmem_rdata(dr), .retire_valid(rv), .retire_pc(rpc),
      .retire_insn(ri), .retire_rd_we(rwe), .retire_rd(rr), .retire_rd_data(rd),
      .event_stall_load(es), .event_fwd_ex_count(ef), .event_fwd_wb_count(wf),
      .event_flush(fl), .event_branch(br), .event_branch_taken(bt),
      .event_custom_crc(crc)
  );
  imem #(.HEX_FILE(IMEM_HEX)) im (.addr(ia), .rdata(id));
  dmem dm (
      .clk(clk), .rst(rst), .we(dv && dwe), .addr(da), .wdata(dw),
      .rdata(dmem_rdata)
  );
  mmio_decoder bus (
      .clk(clk), .rst(rst), .valid(dv), .we(dwe), .addr(da), .wdata(dw),
      .sw(sw), .btn(btn), .capture_in(capture_in), .uart_rx_i(uart_rx),
      .display_index(display_index), .retire(rv), .stall(es), .fwd_ex(ef),
      .fwd_wb(wf), .flush(fl), .branch(br), .branch_taken(bt), .crc(crc),
      .rdata(mmio_r), .led(led), .test_result(test_result), .uart_tx(uart_tx),
      .pwm_out(pwm_out), .pattern_out(pattern_out),
      .pattern_enabled(pattern_enabled), .capture_sample(cs),
      .display_sample(display_sample), .capture_armed(ca),
      .capture_triggered(ct), .capture_done(capture_done), .seg_an(seg_an),
      .seg(seg), .seg_dp(seg_dp)
  );
  vga_waveform waveform (
      .clk(clk), .rst(rst), .sample(display_sample),
      .sample_index(display_index), .vga_r(vga_r), .vga_g(vga_g),
      .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs)
  );
  assign dr = (da[31:28] == 4'h4) ? mmio_r : dmem_rdata;
endmodule
`default_nettype wire
