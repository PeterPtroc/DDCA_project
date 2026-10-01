`default_nettype none
module nexys_a7_top (
    input wire clk100,
    input wire reset_n,
    input wire [15:0] sw,
    input wire [4:0] btn,
    output wire [15:0] led,
    input wire uart_rx,
    output wire uart_tx,
    output wire [7:0] pmod_ja,
    input wire [7:0] pmod_jb,
    output wire [7:0] seg_an,
    output wire [6:0] seg,
    output wire seg_dp,
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire vga_hs,
    output wire vga_vs
);
  wire reset = ~reset_n;
  wire pwm_out;
  wire [7:0] pattern_out;
  wire pattern_enabled;
  wire [31:0] test_result;
  wire capture_done;

  soc_top soc (
      .clk(clk100), .rst(reset), .sw(sw), .btn(btn), .capture_in(pmod_jb),
      .uart_rx(uart_rx), .led(led), .uart_tx(uart_tx), .pwm_out(pwm_out),
      .pattern_out(pattern_out), .pattern_enabled(pattern_enabled),
      .test_result(test_result), .capture_done(capture_done), .seg_an(seg_an),
      .seg(seg), .seg_dp(seg_dp), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
      .vga_hs(vga_hs), .vga_vs(vga_vs)
  );
  assign pmod_ja = pattern_enabled ? pattern_out : {7'd0, pwm_out};
endmodule
`default_nettype wire
