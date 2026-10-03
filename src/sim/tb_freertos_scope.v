`default_nettype none
module tb_freertos_scope;
  localparam [31:0] PASS_VALUE = 32'h600d600d;

  reg clk = 1'b0;
  reg rst = 1'b1;
  reg uart_rx_line = 1'b1;
  reg scope_signal = 1'b0;
  integer scope_div = 0;
  integer cycles = 0;
  integer rx_count = 0;
  integer start;
  integer index;
  reg [7:0] rx_bytes [0:1023];
  reg [15:0] crc;
  wire uart_tx_line;
  wire [7:0] monitor_data;
  wire monitor_valid;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst) begin
      scope_signal <= 1'b0;
      scope_div <= 0;
      cycles <= 0;
    end else begin
      cycles <= cycles + 1;
      if (cycles > 3000000) $fatal(1, "FreeRTOS scope integration timeout");
      if (scope_div == 499) begin
        scope_div <= 0;
        scope_signal <= ~scope_signal;
      end else scope_div <= scope_div + 1;
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
      .capture_in({7'd0, scope_signal}), .uart_rx(uart_rx_line),
      .led(), .uart_tx(uart_tx_line), .seg_an(), .seg(), .seg_dp(),
      .rgb0_r(), .rgb0_g(), .rgb0_b(), .rgb1_r(), .rgb1_g(), .rgb1_b()
  );

  uart_rx #(.DIVIDER(16)) monitor (
      .clk(clk), .rst(rst), .rx(uart_tx_line),
      .data(monitor_data), .valid(monitor_valid)
  );

  always @(posedge clk) begin
    if (monitor_valid) begin
      rx_bytes[rx_count] <= monitor_data;
      rx_count <= rx_count + 1;
    end
  end

  task uart_bit;
    input value;
    integer n;
    begin
      uart_rx_line = value;
      for (n = 0; n < 16; n = n + 1) @(posedge clk);
    end
  endtask

  task uart_send;
    input [7:0] value;
    integer n;
    begin
      uart_bit(1'b0);
      for (n = 0; n < 8; n = n + 1) uart_bit(value[n]);
      uart_bit(1'b1);
      uart_bit(1'b1);
    end
  endtask

  task wait_for_bytes;
    input integer target;
    input integer limit;
    integer n;
    begin
      n = 0;
      while (rx_count < target && n < limit) begin
        @(posedge clk);
        n = n + 1;
      end
      if (rx_count < target)
        $fatal(1, "UART timeout bytes=%0d target=%0d", rx_count, target);
      @(posedge clk);
    end
  endtask

  task wait_for_live_hold;
    input expected;
    integer n;
    begin
      n = 0;
      while (dut.bus.live_hold !== expected && n < 150000) begin
        @(posedge clk);
        n = n + 1;
      end
      if (dut.bus.live_hold !== expected)
        $fatal(1, "UART live hold command timeout expected=%0d", expected);
    end
  endtask

  function [15:0] crc16_byte;
    input [15:0] old_crc;
    input [7:0] data;
    integer bit_index;
    reg [15:0] value;
    begin
      value = old_crc ^ data;
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
        value = value[0] ? (value >> 1) ^ 16'ha001 : value >> 1;
      crc16_byte = value;
    end
  endfunction

  initial begin
    repeat (10) @(posedge clk);
    rst = 1'b0;

    while (dut.test_result != PASS_VALUE && cycles < 600000) @(posedge clk);
    if (dut.test_result != PASS_VALUE)
      $fatal(1, "FreeRTOS tasks did not reach pass state result=%08x", dut.test_result);

    start = rx_count;
    uart_send("s");
    wait_for_bytes(start + 5, 150000);
    if (rx_bytes[start] != "S" || rx_bytes[start+1] != "C" ||
        rx_bytes[start+2] != "P" || rx_bytes[start+3] != "2" ||
        rx_bytes[start+4] != 8'h0a)
      $fatal(1, "FreeRTOS status response mismatch");

    uart_send("h");
    wait_for_live_hold(1'b1);
    uart_send("r");
    wait_for_live_hold(1'b0);

    start = rx_count;
    uart_send("m");
    wait_for_bytes(start + 24, 150000);
    if (rx_bytes[start] != "M" || rx_bytes[start+1] != "E" ||
        rx_bytes[start+2] != "A" || rx_bytes[start+3] != "2")
      $fatal(1, "FreeRTOS measurement response mismatch");

    start = rx_count;
    uart_send("p");
    wait_for_bytes(start + 40, 150000);
    if (rx_bytes[start] != "P" || rx_bytes[start+1] != "R" ||
        rx_bytes[start+2] != "F" || rx_bytes[start+3] != "2")
      $fatal(1, "FreeRTOS performance response mismatch");

    // Accelerate only the capture RAM sampling interval; all task, command,
    // packet and UART timing remains cycle accurate.
    force dut.bus.cap.sample_div = 32'd1;
    uart_send("1");
    index = 0;
    while (!dut.bus.capture_done && index < 170000) begin
      @(posedge clk);
      index = index + 1;
    end
    if (!dut.bus.capture_done) $fatal(1, "FreeRTOS SINGLE capture timeout");

    start = rx_count;
    uart_send("d");
    wait_for_bytes(start + 540, 400000);
    if (rx_bytes[start] != "C" || rx_bytes[start+1] != "A" ||
        rx_bytes[start+2] != "P" || rx_bytes[start+3] != "2" ||
        rx_bytes[start+4] != 2 || rx_bytes[start+6] != 0 ||
        rx_bytes[start+7] != 16)
      $fatal(1, "FreeRTOS CAP2 header mismatch");
    crc = 16'hffff;
    for (index = 0; index < 538; index = index + 1)
      crc = crc16_byte(crc, rx_bytes[start+index]);
    if (rx_bytes[start+538] != crc[7:0] ||
        rx_bytes[start+539] != crc[15:8])
      $fatal(1, "FreeRTOS CAP2 CRC mismatch got=%02x%02x expected=%04x",
             rx_bytes[start+539], rx_bytes[start+538], crc);
    if (dut.bus.perf.crc_c < 538)
      $fatal(1, "CRC16.B was not used for CAP2 crc_count=%0d", dut.bus.perf.crc_c);
    release dut.bus.cap.sample_div;

    $display("FREERTOS SCOPE PASS: commands=6 cap2_bytes=540 crc=%04x crc_insn=%0d",
             crc, dut.bus.perf.crc_c);
    $finish;
  end
endmodule
`default_nettype wire
