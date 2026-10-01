
module tb_soc_mvp;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [15:0] sw = 16'd0;
  reg [4:0] btn = 5'd0;
  wire [7:0] capture_in;
  wire [15:0] led;
  wire uart_tx;
  wire pwm_out;
  wire [31:0] test_result;
  wire capture_done;
  reg uart_started = 1'b0;
  integer cycles;

  always #5 clk = ~clk;
  assign capture_in = {7'd0, pwm_out};

  soc_top #(.IMEM_HEX("build/hex/mvp.hex")) dut (
      .clk(clk),
      .rst(rst),
      .sw(sw),
      .btn(btn),
      .capture_in(capture_in),
      .uart_rx(1'b1),
      .led(led),
      .uart_tx(uart_tx),
      .pwm_out(pwm_out),
      .pattern_out(),
      .pattern_enabled(),
      .test_result(test_result),
      .capture_done(capture_done),
      .seg_an(),
      .seg(),
      .seg_dp(),
      .vga_r(),
      .vga_g(),
      .vga_b(),
      .vga_hs(),
      .vga_vs()
  );

  always @(negedge uart_tx) begin
    if (!rst) uart_started = 1'b1;
  end

  initial begin
    repeat (10) @(posedge clk);
    rst = 1'b0;

    for (cycles = 0; cycles < 300000; cycles = cycles + 1) begin
      @(posedge clk);
      if (test_result === 32'hdead0000)
        $fatal(1, "MVP firmware reported FAIL at cycle %0d", cycles);
      if (test_result === 32'h600d600d) begin
        if (!capture_done) $fatal(1, "PASS published before Capture completed");
        if (dut.bus.cap.depth !== 13'd32)
          $fatal(1, "Capture depth mismatch: %0d", dut.bus.cap.depth);
        if (dut.bus.pwm.period !== 32'd8 || dut.bus.pwm.high !== 32'd4)
          $fatal(
              1,
              "PWM configuration mismatch: period=%0d high=%0d",
              dut.bus.pwm.period,
              dut.bus.pwm.high
          );
        if (!uart_started) $fatal(1, "PASS published without a UART transmission");
        $display("MVP PASS: cycles=%0d capture_count=%0d", cycles, dut.bus.cap.count);
        $finish;
      end
    end

    $fatal(1, "MVP timeout: result=%h capture_done=%b", test_result, capture_done);
  end
endmodule
