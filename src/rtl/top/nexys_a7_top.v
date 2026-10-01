`default_nettype none
module nexys_a7_top (
    input wire clk100,
    input wire reset_n,
    input wire [15:0] sw,
    input wire [4:0] btn,
    output wire [15:0] led,
    input wire uart_rx,
    output wire uart_tx,
    output wire ja1,
    input wire jb1,
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
  // Assert reset immediately but release it through two clocked stages so the
  // external push button cannot deassert the SoC reset near a clock edge.
  (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync = 2'b00;
  always @(posedge clk100 or negedge reset_n) begin
    if (!reset_n) reset_sync <= 2'b00;
    else reset_sync <= {reset_sync[0], 1'b1};
  end
  wire reset = ~reset_sync[1];
  wire pwm_out;
  wire [31:0] test_result;
  wire capture_done;

  soc_top soc (
      .clk(clk100), .rst(reset), .sw(sw), .btn(btn),
      .capture_in({7'd0, jb1}),
      .uart_rx(uart_rx), .led(led), .uart_tx(uart_tx), .pwm_out(pwm_out),
      .pattern_out(), .pattern_enabled(),
      .test_result(test_result), .capture_done(capture_done), .seg_an(seg_an),
      .seg(seg), .seg_dp(seg_dp), .rgb0_r(rgb0_r), .rgb0_g(rgb0_g), .rgb0_b(rgb0_b),
      .rgb1_r(rgb1_r), .rgb1_g(rgb1_g), .rgb1_b(rgb1_b),
      .vga_r(), .vga_g(), .vga_b(), .vga_hs(), .vga_vs()
  );
  assign ja1 = pwm_out;
endmodule
`default_nettype wire
