`default_nettype none
module tb_freertos_smoke;
  localparam [31:0] PASS_VALUE = 32'h600d600d;

  reg clk = 1'b0;
  reg rst = 1'b1;
  reg scope_signal = 1'b0;
  integer scope_div = 0;
  integer cycles = 0;
  integer ecall_count = 0;
  integer timer_irq_count = 0;

  wire [15:0] led;
  wire uart_tx;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst) begin
      scope_signal <= 1'b0;
      scope_div <= 0;
    end else if (scope_div == 499) begin
      scope_div <= 0;
      scope_signal <= ~scope_signal;
    end else begin
      scope_div <= scope_div + 1;
    end
  end

  soc_top #(
      .IMEM_HEX("build/hex/freertos.hex"),
      .BUTTON_DEBOUNCE_BITS(2),
      .UART_DIVIDER(16),
      .EDGE_MIN_TIMEOUT_TICKS(2000),
      .EDGE_INITIAL_TIMEOUT_TICKS(4000),
      .LIVE_AUTO_TIMEOUT_SAMPLES(32)
  ) dut (
      .clk(clk), .rst(rst), .sw(16'd0), .btn(5'd0),
      .capture_in({7'd0, scope_signal}), .uart_rx(1'b1),
      .led(led), .uart_tx(uart_tx), .seg_an(), .seg(), .seg_dp(),
      .rgb0_r(), .rgb0_g(), .rgb0_b(), .rgb1_r(), .rgb1_g(), .rgb1_b()
  );

  initial begin
    repeat (10) @(posedge clk);
    rst = 1'b0;
  end

  always @(posedge clk) begin
    if (rst) begin
      cycles <= 0;
      ecall_count <= 0;
      timer_irq_count <= 0;
    end else begin
      cycles <= cycles + 1;
      if (cycles > 600000) $fatal(1, "FreeRTOS smoke timeout result=%08x", dut.test_result);

      if (dut.cpu.trap_taken) begin
        if (dut.cpu.trap_cause == 32'd11) ecall_count <= ecall_count + 1;
        else if (dut.cpu.trap_cause == 32'h80000007)
          timer_irq_count <= timer_irq_count + 1;
        else
          $fatal(1, "unexpected FreeRTOS trap cause=%08x pc=%08x",
                 dut.cpu.trap_cause, dut.cpu.csr_mepc);
      end

      if (dut.test_result[31:16] == 16'hdead)
        $fatal(1, "FreeRTOS firmware failure=%08x", dut.test_result);

      if (dut.test_result == PASS_VALUE) begin
        if (ecall_count < 4)
          $fatal(1, "too few blocking context switches: %0d", ecall_count);
        if (timer_irq_count < 2)
          $fatal(1, "preemptive tick did not run twice: %0d", timer_irq_count);
        if (dut.cpu.csr_minstret < 500)
          $fatal(1, "implausibly low retired instruction count: %0d",
                 dut.cpu.csr_minstret);
        $display("FREERTOS SMOKE PASS: cycles=%0d ecall=%0d ticks=%0d instret=%0d",
                 cycles, ecall_count, timer_irq_count, dut.cpu.csr_minstret);
        $finish;
      end
    end
  end
endmodule
`default_nettype wire

