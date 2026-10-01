module tb_edge_meter_scope;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg sample = 1'b0;
  reg we = 1'b0;
  reg [4:0] off = 5'd0;
  reg [31:0] wdata = 32'd0;
  wire [31:0] rdata, period, high, low, frequency, age;
  wire valid, present, averaging;
  always #5 clk = ~clk;

  edge_meter_scope #(.CLOCK_HZ(1000), .MIN_TIMEOUT_TICKS(100),
      .INITIAL_TIMEOUT_TICKS(40)) dut (
      .clk(clk), .rst(rst), .sample(sample), .we(we), .off(off), .wdata(wdata),
      .rdata(rdata), .valid(valid), .signal_present(present),
      .averaging(averaging), .period_ticks(period), .high_ticks(high),
      .low_ticks(low), .frequency_hz(frequency), .edge_age(age)
  );

  task write_reg;
    input [4:0] a;
    input [31:0] d;
    begin
      @(negedge clk); off = a; wdata = d; we = 1'b1;
      @(negedge clk); we = 1'b0;
    end
  endtask
  task level;
    input value;
    input integer clocks;
    integer n;
    begin
      @(negedge clk); sample = value;
      for (n = 0; n < clocks; n = n + 1) @(posedge clk);
    end
  endtask

  integer i;
  initial begin
    repeat (3) @(posedge clk);
    rst = 1'b0;
    level(1'b0, 3);
    level(1'b1, 4);
    level(1'b0, 6);
    level(1'b1, 4);
    level(1'b0, 6);
    repeat (40) @(posedge clk);
    #1;
    if (!valid || !present || period !== 32'd10 || high !== 32'd4 ||
        low !== 32'd6 || frequency !== 32'd100)
      $fatal(1, "measurement mismatch v=%b p=%b period=%0d high=%0d low=%0d freq=%0d",
          valid, present, period, high, low, frequency);

    write_reg(5'h00, 32'b111);
    if (!averaging) $fatal(1, "averaging control was not accepted");
    // Four completed periods are 8, 10, 12 and 14 clocks.  Both the
    // reported period and the frequency must use their average (11).
    for (i = 0; i < 5; i = i + 1) begin
      level(1'b1, 4);
      level(1'b0, 4 + (i * 2));
    end
    repeat (40) @(posedge clk);
    if (period !== 32'd11 || high !== 32'd4 || frequency !== 32'd90)
      $fatal(1, "averaged measurement mismatch period=%0d high=%0d freq=%0d",
          period, high, frequency);

    repeat (120) @(posedge clk);
    if (valid || present) $fatal(1, "no-signal timeout did not clear result");
    $display("EDGE METER SCOPE PASS");
    $finish;
  end
endmodule
