module tb_soc_analyzer;
  reg clk = 1'b0;
  reg rst = 1'b1;
  wire [7:0] capture_in;
  wire [7:0] pattern_out;
  wire pattern_enabled;
  wire [31:0] test_result;
  wire capture_done;
  wire uart_tx;
  integer cycles;
  reg uart_started = 1'b0;
  always #5 clk = ~clk;
  assign capture_in = pattern_out;

  soc_top #(.IMEM_HEX("build/hex/analyzer.hex"), .ENABLE_LEGACY_PATTERN(1)) dut (
      .clk(clk), .rst(rst), .sw(16'd0), .btn(5'd0),
      .capture_in(capture_in), .uart_rx(1'b1), .led(), .uart_tx(uart_tx),
      .pwm_out(), .pattern_out(pattern_out), .pattern_enabled(pattern_enabled),
      .test_result(test_result), .capture_done(capture_done), .seg_an(),
      .seg(), .seg_dp(), .vga_r(), .vga_g(), .vga_b(), .vga_hs(), .vga_vs()
  );

  always @(negedge uart_tx) if (!rst) uart_started = 1'b1;

  initial begin
    repeat (10) @(posedge clk);
    rst = 1'b0;
    for (cycles = 0; cycles < 500000; cycles = cycles + 1) begin
      @(posedge clk);
      if (test_result === 32'h600d600d) begin
        if (!pattern_enabled || !capture_done || !uart_started)
          $fatal(1, "analyzer PASS without generator/capture/UART closure");
        if (dut.dm.mem[0] < 32'd255 || dut.dm.mem[0] > 32'd257)
          $fatal(1, "multi-period average mismatch: %0d", dut.dm.mem[0]);
        if (dut.dm.mem[1] < 32'd76 || dut.dm.mem[1] > 32'd78)
          $fatal(1, "high average mismatch: %0d", dut.dm.mem[1]);
        $display("SOC ANALYZER PASS: cycles=%0d period=%0d high=%0d freq=%0d",
                 cycles, dut.dm.mem[0], dut.dm.mem[1], dut.dm.mem[2]);
        $finish;
      end
    end
    $fatal(1, "analyzer timeout: result=%h done=%b pc=%h", test_result,
           capture_done, dut.cpu.pc);
  end
endmodule
