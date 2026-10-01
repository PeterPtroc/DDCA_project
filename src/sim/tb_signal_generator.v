module tb_signal_generator;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg we = 1'b0;
  reg [4:0] off = 5'd0;
  reg [31:0] wdata = 32'd0;
  wire [31:0] rdata;
  wire enabled, signal_out;
  wire [31:0] period_ticks, high_ticks;
  always #5 clk = ~clk;
  signal_generator dut (.clk(clk), .rst(rst), .we(we), .off(off), .wdata(wdata),
      .rdata(rdata), .enabled(enabled), .signal_out(signal_out),
      .period_ticks(period_ticks), .high_ticks(high_ticks));

  task write_reg;
    input [4:0] a;
    input [31:0] d;
    begin
      @(negedge clk); off = a; wdata = d; we = 1'b1;
      @(negedge clk); we = 1'b0;
    end
  endtask

  integer high_count;
  integer i;
  initial begin
    repeat (3) @(posedge clk);
    rst = 1'b0;
    write_reg(5'h04, 10);
    write_reg(5'h08, 3);
    write_reg(5'h00, 1);
    high_count = 0;
    for (i = 0; i < 10; i = i + 1) begin
      @(posedge clk);
      if (signal_out) high_count = high_count + 1;
    end
    if (high_count !== 3) $fatal(1, "generator duty mismatch: %0d", high_count);
    if (enabled !== 1'b1 || period_ticks !== 32'd10 || high_ticks !== 32'd3)
      $fatal(1, "generator enable status mismatch");
    write_reg(5'h08, 20);
    if (high_ticks !== 32'd10) $fatal(1, "generator high clamp failed");
    write_reg(5'h00, 0);
    repeat (2) @(posedge clk);
    if (signal_out || enabled) $fatal(1, "disabled generator was not LOW");
    $display("SIGNAL GENERATOR PASS");
    $finish;
  end
endmodule
