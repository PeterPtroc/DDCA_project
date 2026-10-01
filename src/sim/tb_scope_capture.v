module tb_scope_capture;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg signal = 1'b0;
  reg we = 1'b0;
  reg [5:0] off = 6'd0;
  reg [31:0] wdata = 32'd0;
  reg window_sel = 1'b0;
  reg [11:0] window_index = 12'd0;
  wire [31:0] rdata;
  wire [7:0] display_sample;
  wire armed, triggered, done;
  wire [12:0] count;
  wire [11:0] trigger_index;
  always #5 clk = ~clk;

  scope_capture dut (.clk(clk), .rst(rst), .scope_signal(signal), .we(we),
      .off(off), .wdata(wdata), .window_sel(window_sel),
      .window_index(window_index), .rdata(rdata), .display_sample(display_sample),
      .armed(armed), .triggered(triggered), .done(done), .count(count),
      .trigger_index(trigger_index));

  task write_reg;
    input [5:0] a;
    input [31:0] d;
    begin
      @(negedge clk); off = a; wdata = d; we = 1'b1;
      @(negedge clk); we = 1'b0;
    end
  endtask

  integer i;
  initial begin
    repeat (3) @(posedge clk);
    rst = 1'b0;
    write_reg(6'h08, 0);
    write_reg(6'h0c, 1);
    write_reg(6'h00, 1);
    for (i = 0; i < 2048; i = i + 1) begin
      signal = 1'b0;
      @(posedge clk);
    end
    @(negedge clk); signal = 1'b1; #1;
    @(posedge clk); #1;
    signal = 1'b0;
    for (i = 0; i < 2048; i = i + 1) @(posedge clk);
    if (!done || count !== 13'd4096 || trigger_index !== 12'd2048)
      $fatal(1, "deep capture mismatch done=%b count=%0d trigger=%0d",
          done, count, trigger_index);
    window_sel = 1'b1;
    window_index = 12'd2048;
    #1;
    if (display_sample[0] !== 1'b1)
      $fatal(1, "trigger sample not at chronological index 2048");

    // Re-arm on a falling edge and verify the same chronological contract.
    window_sel = 1'b0;
    @(negedge clk); signal = 1'b1;
    write_reg(6'h00, 2);
    write_reg(6'h08, 1);
    write_reg(6'h00, 1);
    for (i = 0; i < 2048; i = i + 1) @(posedge clk);
    @(negedge clk); signal = 1'b0;
    @(posedge clk);
    for (i = 0; i < 2048; i = i + 1) @(posedge clk);
    if (!done || count !== 13'd4096 || trigger_index !== 12'd2048)
      $fatal(1, "falling deep capture mismatch");
    window_sel = 1'b1;
    window_index = 12'd2048;
    #1;
    if (display_sample[0] !== 1'b0)
      $fatal(1, "falling trigger sample not at chronological index 2048");

    // A narrow edge between divided sample ticks must still trigger. The old
    // sample-tick-only detector could alias a periodic input to a constant and
    // leave the firmware dump loop blocked forever.
    window_sel = 1'b0;
    write_reg(6'h00, 2);
    write_reg(6'h08, 0);
    write_reg(6'h0c, 10);
    signal = 1'b0;
    write_reg(6'h00, 1);
    for (i = 0; i < 20490; i = i + 1) @(posedge clk);
    repeat (3) @(posedge clk);
    @(negedge clk); signal = 1'b1;
    @(posedge clk); #1;
    if (!triggered)
      $fatal(1, "full-rate edge between sample ticks did not trigger");
    @(negedge clk); signal = 1'b0;
    for (i = 0; i < 20490; i = i + 1) @(posedge clk);
    if (!done || count !== 13'd4096 || trigger_index !== 12'd2048)
      $fatal(1, "divided capture did not complete after full-rate trigger");
    $display("SCOPE CAPTURE PASS");
    $finish;
  end
endmodule
