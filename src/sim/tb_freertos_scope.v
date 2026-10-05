`default_nettype none
module tb_freertos_scope #(
    parameter UART_DIVIDER = 16,
    parameter BURST_ONLY = 0
);
  localparam [31:0] PASS_VALUE = 32'h600d600d;

  reg clk = 1'b0;
  reg rst = 1'b1;
  reg uart_rx_line = 1'b1;
  reg scope_signal = 1'b0;
  reg signal_enable = 1'b1;
  reg [15:0] switches = 0;
  reg [4:0] buttons = 0;
  reg [63:0] timeout_time;
  integer scope_div = 0;
  integer cycles = 0;
  integer rx_count = 0;
  integer start;
  integer index;
  integer arms = 0;
  integer previous_arms;
  reg [7:0] rx_bytes [0:2047];
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
      if (cycles > 10000000) $fatal(1, "FreeRTOS scope integration timeout");
      if (!signal_enable) begin
        scope_div <= 0;
        scope_signal <= 0;
      end else if (scope_div == 499) begin
        scope_div <= 0;
        scope_signal <= ~scope_signal;
      end else scope_div <= scope_div + 1;
    end
  end

  soc_top #(
      .IMEM_HEX("build/hex/freertos.hex"),
      .BUTTON_DEBOUNCE_BITS(2),
      .UART_DIVIDER(UART_DIVIDER),
      .EDGE_MIN_TIMEOUT_TICKS(2000),
      .EDGE_INITIAL_TIMEOUT_TICKS(4000),
      .LIVE_AUTO_TIMEOUT_SAMPLES(32)
  ) dut (
      .clk(clk), .rst(rst), .sw(switches), .btn(buttons),
      .capture_in({7'd0, scope_signal}), .uart_rx(uart_rx_line),
      .led(), .uart_tx(uart_tx_line), .seg_an(), .seg(), .seg_dp(),
      .rgb0_r(), .rgb0_g(), .rgb0_b(), .rgb1_r(), .rgb1_g(), .rgb1_b()
  );

  uart_rx #(.DIVIDER(UART_DIVIDER)) monitor (
      .clk(clk), .rst(rst), .rx(uart_tx_line),
      .data(monitor_data), .valid(monitor_valid)
  );

  always @(posedge clk) begin
    if (!rst && dut.dv && dut.dwe && dut.da == 32'h40004000 && dut.dw[0])
      arms <= arms + 1;
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
      for (n = 0; n < UART_DIVIDER; n = n + 1) @(negedge clk);
    end
  endtask

  task uart_send;
    input [7:0] value;
    integer n;
    begin
      uart_bit(1'b0);
      for (n = 0; n < 8; n = n + 1) uart_bit(value[n]);
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
      @(negedge clk);
    end
  endtask

  task wait_for_arm;
    input integer previous_count;
    integer n;
    begin
      n = 0;
      while (arms == previous_count && n < 200000) begin
        @(negedge clk);
        n = n + 1;
      end
      if (arms == previous_count) $fatal(1, "new capture request was not consumed");
    end
  endtask

  task check_error;
    input integer position;
    input [8*16-1:0] expected;
    input integer length;
    integer n;
    begin
      for (n = 0; n < length; n = n + 1)
        if (rx_bytes[position+n] != expected[(length-1-n)*8 +: 8])
          $fatal(1, "capture error response mismatch at byte %0d", n);
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
    repeat (10) @(negedge clk);
    rst = 1'b0;

    while (dut.test_result != PASS_VALUE && cycles < 600000) @(posedge clk);
    if (dut.test_result != PASS_VALUE)
      $fatal(1, "FreeRTOS tasks did not reach pass state result=%08x", dut.test_result);

    // The tasks can start before the boot banner finishes at the real baud.
    // Observe its complete response, then inject just after an empty RX poll
    // so both commands arrive within the following 1 ms task delay.
    wait_for_bytes(32, 600000);
    index = 0;
    while (!(dut.dv && !dut.dwe && dut.da == 32'h40001004 && !dut.bus.uart.rx_valid) &&
           index < 150000) begin
      @(negedge clk);
      index = index + 1;
    end
    if (index == 150000) $fatal(1, "UART task did not poll RX");

    start = rx_count;
    uart_send("s");
    uart_send("m");
    wait_for_bytes(start + 29, 600000);
    if (rx_bytes[start] != "S" || rx_bytes[start+1] != "C" ||
        rx_bytes[start+2] != "P" || rx_bytes[start+3] != "2" ||
        rx_bytes[start+4] != 8'h0a)
      $fatal(1, "FreeRTOS status response mismatch");
    if (rx_bytes[start+5] != "M" || rx_bytes[start+6] != "E" ||
        rx_bytes[start+7] != "A" || rx_bytes[start+8] != "2")
      $fatal(1, "FreeRTOS back-to-back s,m command lost or reordered");
    if (BURST_ONLY) begin
      $display("FREERTOS UART BURST PASS: divider=868, back-to-back s,m, responses=29 bytes");
      $finish;
    end

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

    uart_send("1");
    index = 0;
    while (!dut.bus.capture_done && index < 1200000) begin
      @(posedge clk);
      index = index + 1;
    end
    if (!dut.bus.capture_done) $fatal(1, "FreeRTOS SINGLE capture timeout");

    // Change real board settings after the 200/rising acquisition completes.
    // The old samples and their metadata must remain intact.
    switches = 16'd1;
    buttons = 5'b10000;
    index = 0;
    while (dut.bus.cap.sample_div != 500 && index < 1200000) begin
      @(negedge clk);
      index = index + 1;
    end
    buttons = 0;
    if (dut.bus.cap.sample_div != 500 || !dut.bus.cap.trigger_edge)
      $fatal(1, "UI did not apply the new capture settings");

    start = rx_count;
    uart_send("d");
    wait_for_bytes(start + 540, 400000);
    if (rx_bytes[start] != "C" || rx_bytes[start+1] != "A" ||
        rx_bytes[start+2] != "P" || rx_bytes[start+3] != "2" ||
        rx_bytes[start+4] != 2 || rx_bytes[start+6] != 0 ||
        rx_bytes[start+7] != 16)
      $fatal(1, "FreeRTOS CAP2 header mismatch");
    if (rx_bytes[start+5] != 0 ||
        {rx_bytes[start+11], rx_bytes[start+10], rx_bytes[start+9], rx_bytes[start+8]} != 200 ||
        {rx_bytes[start+17], rx_bytes[start+16], rx_bytes[start+15], rx_bytes[start+14]} != 1000)
      $fatal(1, "completed capture was relabelled with current settings");
    crc = 16'hffff;
    for (index = 0; index < 538; index = index + 1)
      crc = crc16_byte(crc, rx_bytes[start+index]);
    if (rx_bytes[start+538] != crc[7:0] ||
        rx_bytes[start+539] != crc[15:8])
      $fatal(1, "FreeRTOS CAP2 CRC mismatch got=%02x%02x expected=%04x",
             rx_bytes[start+539], rx_bytes[start+538], crc);
    if (dut.bus.perf.crc_c < 538)
      $fatal(1, "CRC16.B was not used for CAP2 crc_count=%0d", dut.bus.perf.crc_c);

    // Discard the old result, then prove SINGLE and cancel remain serviceable
    // while a dump is waiting for a trigger that never arrives.
    signal_enable = 0;
    start = rx_count;
    uart_send("c");
    wait_for_bytes(start + 15, 200000);
    check_error(start, "ERR2 CANCELLED\n", 15);
    previous_arms = arms;
    uart_send("d");
    wait_for_arm(previous_arms);
    previous_arms = arms;
    uart_send("1");
    wait_for_arm(previous_arms);
    start = rx_count;
    uart_send("c");
    wait_for_bytes(start + 15, 200000);
    check_error(start, "ERR2 CANCELLED\n", 15);
    if (dut.bus.capture_armed || dut.bus.capture_done)
      $fatal(1, "cancel did not reset capture hardware");

    start = rx_count;
    previous_arms = arms;
    uart_send("d");
    wait_for_arm(previous_arms);
    // Advance only CLINT time to exercise the production 1021-tick deadline.
    // The official port still handles each tick; no firmware state is forced.
    timeout_time = dut.machine_timer.mtime + 64'd110000000;
    force dut.machine_timer.mtime = timeout_time;
    wait_for_bytes(start + 13, 5000000);
    check_error(start, "ERR2 TIMEOUT\n", 13);
    release dut.machine_timer.mtime;
    if (dut.bus.capture_armed || dut.bus.capture_done)
      $fatal(1, "timeout did not reset capture hardware");

    // A fresh export after the failed request must use the new 500/falling
    // configuration and must not emit a leftover response from that request.
    signal_enable = 1;
    start = rx_count;
    uart_send("d");
    wait_for_bytes(start + 540, 2700000);
    if ({rx_bytes[start+3], rx_bytes[start+2], rx_bytes[start+1], rx_bytes[start]} != 32'h32504143 ||
        rx_bytes[start+5] != 1 ||
        {rx_bytes[start+11], rx_bytes[start+10], rx_bytes[start+9], rx_bytes[start+8]} != 500)
      $fatal(1, "capture did not recover after timeout");
    crc = 16'hffff;
    for (index = 0; index < 538; index = index + 1)
      crc = crc16_byte(crc, rx_bytes[start+index]);
    if ({rx_bytes[start+539], rx_bytes[start+538]} != crc)
      $fatal(1, "recovered capture CRC mismatch");

    $display("FREERTOS SCOPE PASS: burst, frozen CAP2, pending SINGLE, cancel, timeout, recovery; crc=%04x crc_insn=%0d",
             crc, dut.bus.perf.crc_c);
    $finish;
  end
endmodule

module tb_freertos_uart_burst;
  tb_freertos_scope #(.UART_DIVIDER(868), .BURST_ONLY(1)) test();
endmodule
`default_nettype wire
