module tb_soc_realtime_scope;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [15:0] sw = 16'h0006; // FREE mode; unused switches stay low
  reg [4:0] btn = 5'd0;
  reg uart_rx_line = 1'b1;
  reg loopback_enable = 1'b1;
  reg [2:0] test_select = 3'd6; // JA9: 100 kHz / 80%
  wire [15:0] led;
  wire uart_tx_line;
  wire [7:0] fixed_test_out;
  wire capture_done;
  wire rgb0_r, rgb0_g, rgb0_b, rgb1_r, rgb1_g, rgb1_b;
  wire [7:0] monitor_data;
  wire monitor_valid;
  reg [7:0] rx_bytes [0:2047];
  integer rx_count = 0;
  integer i;
  integer start;
  reg [31:0] frame_before;
  reg [15:0] crc;

  always #5 clk = ~clk;
  wire [7:0] capture_in = {7'd0,
      loopback_enable ? fixed_test_out[test_select] : 1'b0};

  fixed_test_signals fixed_signals (
      .clk(clk), .rst(rst), .test_out(fixed_test_out)
  );

  soc_top #(
      .IMEM_HEX("build/hex/scope.hex"),
      .BUTTON_DEBOUNCE_BITS(2),
      .UART_DIVIDER(16),
      .EDGE_MIN_TIMEOUT_TICKS(2000),
      .EDGE_INITIAL_TIMEOUT_TICKS(4000),
      .LIVE_AUTO_TIMEOUT_SAMPLES(32)
  ) dut (
      .clk(clk), .rst(rst), .sw(sw), .btn(btn), .capture_in(capture_in),
      .uart_rx(uart_rx_line), .led(led), .uart_tx(uart_tx_line),
      .seg_an(), .seg(), .seg_dp(),
      .rgb0_r(rgb0_r), .rgb0_g(rgb0_g), .rgb0_b(rgb0_b),
      .rgb1_r(rgb1_r), .rgb1_g(rgb1_g), .rgb1_b(rgb1_b)
  );
  assign capture_done = dut.bus.capture_done;

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

  task wait_clocks;
    input integer clocks;
    integer n;
    begin
      for (n = 0; n < clocks; n = n + 1) @(posedge clk);
    end
  endtask

  task press_button;
    input integer bit_index;
    begin
      @(negedge clk); btn[bit_index] = 1'b1;
      wait_clocks(10);
      @(negedge clk); btn[bit_index] = 1'b0;
      wait_clocks(500);
    end
  endtask

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

  function [15:0] crc16_byte;
    input [15:0] old_crc;
    input [7:0] data;
    integer bit_index;
    reg [15:0] value;
    begin
      value = old_crc ^ data;
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        if (value[0]) value = (value >> 1) ^ 16'ha001;
        else value = value >> 1;
      end
      crc16_byte = value;
    end
  endfunction

  initial begin
    wait_clocks(10);
    rst = 1'b0;
    wait_clocks(120000);

    // Selectable simulation jumper: JA9 -> JB1.
    if (!dut.bus.edge_valid || dut.bus.edge_frequency !== 32'd100000 ||
        dut.bus.edge_period !== 32'd1000 || dut.bus.edge_high !== 32'd800)
      $fatal(1, "JA9 measurement mismatch valid=%b f=%0d p=%0d h=%0d",
          dut.bus.edge_valid, dut.bus.edge_frequency,
          dut.bus.edge_period, dut.bus.edge_high);

    // Move the simulated Dupont jumper to JA4 and verify its fixed waveform.
    test_select = 3'd3;
    wait_clocks(30000);
    if (!dut.bus.edge_valid || dut.bus.edge_frequency !== 32'd14242 ||
        dut.bus.edge_period !== 32'd7021 || dut.bus.edge_high !== 32'd3511)
      $fatal(1, "JA4 measurement mismatch f=%0d p=%0d h=%0d",
          dut.bus.edge_frequency, dut.bus.edge_period, dut.bus.edge_high);
    test_select = 3'd6;
    wait_clocks(5000);

    if (dut.bus.live_frame_counter < 3 || led === 16'h0000 || led === 16'hffff)
      $fatal(1, "live scope did not publish a useful frame count=%0d led=%h",
          dut.bus.live_frame_counter, led);

    frame_before = dut.bus.live_frame_counter;
    press_button(0);           // HOLD in FREE mode
    dut.dm.mem[4] = dut.bus.timer.timer[31:0] - 32'd5000000;
    wait_clocks(8000);
    wait_clocks(20000);
    if (dut.bus.live_frame_counter !== frame_before || !rgb0_b)
      $fatal(1, "HOLD did not freeze live frame");
    if (dut.bus.display.display_data0 !== 32'h1200150d ||
        dut.bus.display.display_data1 !== 32'h1f1f1f1f)
      $fatal(1, "HOLD display mismatch data=%h_%h",
          dut.bus.display.display_data1, dut.bus.display.display_data0);
    press_button(0);           // RUN
    wait_clocks(20000);
    if (dut.bus.live_frame_counter <= frame_before || !rgb0_g)
      $fatal(1, "RUN did not resume live frame before=%0d after=%0d hold_mem=%0d ctrl=%b run=%b rgb=%b%b%b div=%0d mode=%0d age=%0d",
          frame_before, dut.bus.live_frame_counter, dut.dm.mem[2],
          dut.bus.live_hold, dut.bus.live_running, rgb0_r, rgb0_g, rgb0_b,
          dut.bus.live_sample_div, dut.bus.live_mode, dut.bus.live.auto_age);

    // A SINGLE request without an input edge remains visibly armed.
    loopback_enable = 1'b0;
    sw = 16'h0004;             // SINGLE
    wait_clocks(1000);
    press_button(0);
    dut.dm.mem[4] = dut.bus.timer.timer[31:0] - 32'd5000000;
    wait_clocks(8000);
    if (!dut.bus.capture_armed || {rgb0_r,rgb0_g,rgb0_b} !== 3'b110)
      $fatal(1, "SINGLE armed state missing capture=%b rgb=%b%b%b",
          dut.bus.capture_armed, rgb0_r, rgb0_g, rgb0_b);
    if (dut.bus.display.display_data0 !== 32'h1f1f0a13 ||
        dut.bus.display.display_data1 !== 32'h1f1f1f1f)
      $fatal(1, "ARM display mismatch data=%h_%h",
          dut.bus.display.display_data1, dut.bus.display.display_data0);

    // The existing fatal-result convention must also have an explicit page.
    sw = 16'h0006;             // FREE
    loopback_enable = 1'b1;
    wait_clocks(1000);
    force dut.bus.gpio.test_result = 32'hdead0000;
    dut.dm.mem[4] = dut.bus.timer.timer[31:0] - 32'd5000000;
    wait_clocks(8000);
    if ({rgb0_r,rgb0_g,rgb0_b} !== 3'b100)
      $fatal(1, "ERROR RGB state mismatch rgb=%b%b%b", rgb0_r, rgb0_g, rgb0_b);
    if (dut.bus.display.display_data0 !== 32'h1f0e1313 ||
        dut.bus.display.display_data1 !== 32'h1f1f1f1f)
      $fatal(1, "ERROR display mismatch data=%h_%h",
          dut.bus.display.display_data1, dut.bus.display.display_data0);
    release dut.bus.gpio.test_result;
    dut.bus.gpio.test_result = 32'd0;
    wait_clocks(1000);

    for (i = 0; i < 8; i = i + 1) press_button(1); // fastest timebase
    wait_clocks(1000);
    if (dut.bus.live_sample_div !== 32'd1 || dut.bus.cap.sample_div !== 32'd1)
      $fatal(1, "timebase was not shared: live=%0d deep=%0d",
          dut.bus.live_sample_div, dut.bus.cap.sample_div);

    sw = 16'h0004;             // SINGLE
    wait_clocks(1000);
    press_button(0);           // arm live + deep
    wait_clocks(15000);
    if (!capture_done || dut.bus.cap.count !== 13'd4096 ||
        dut.bus.cap.trigger_index !== 12'd2048 || !dut.bus.live_single_done)
      $fatal(1, "SINGLE/deep capture mismatch done=%b count=%0d trigger=%0d live=%b",
          capture_done, dut.bus.cap.count, dut.bus.cap.trigger_index,
          dut.bus.live_single_done);
    if (dut.dm.mem[2] !== 32'd1)
      $fatal(1, "firmware did not enter HOLD after SINGLE");

    sw = 16'h0006;             // restore switch-selected FREE mode
    wait_clocks(1000);

    // The compact status response remains available over UART.
    start = rx_count;
    uart_send(8'h73);
    wait_clocks(8000);
    if (rx_count - start !== 5 || rx_bytes[start] !== "S" ||
        rx_bytes[start+1] !== "C" || rx_bytes[start+2] !== "P" ||
        rx_bytes[start+3] !== "2" || rx_bytes[start+4] !== 8'h0a)
      $fatal(1, "status UART response mismatch bytes=%0d", rx_count-start);

    // UART HOLD and RUN must control the live data path without button input.
    uart_send(8'h68);
    wait_clocks(1000);
    frame_before = dut.bus.live_frame_counter;
    wait_clocks(3000);
    if (!dut.bus.live_hold || dut.bus.live_frame_counter !== frame_before)
      $fatal(1, "UART HOLD did not freeze live frames");
    uart_send(8'h72);
    wait_clocks(5000);
    if (dut.bus.live_hold || dut.bus.live_mode !== 2'd3 ||
        dut.bus.live_frame_counter <= frame_before)
      $fatal(1, "UART RUN did not restore switch-selected FREE mode");

    // The command must force a genuine SINGLE even while switches select FREE.
    uart_send(8'h31);
    wait_clocks(15000);
    if (dut.bus.live_mode !== 2'd2 || !dut.bus.live_single_done ||
        !capture_done || dut.dm.mem[2] !== 32'd1)
      $fatal(1, "UART SINGLE did not complete and enter HOLD mode=%0d live=%b deep=%b hold=%0d",
          dut.bus.live_mode, dut.bus.live_single_done, capture_done, dut.dm.mem[2]);
    frame_before = dut.bus.live_frame_counter;
    uart_send(8'h72);
    wait_clocks(5000);
    if (dut.bus.live_mode !== 2'd3 || dut.bus.live_hold ||
        dut.bus.live_frame_counter <= frame_before)
      $fatal(1, "UART RUN did not resume after UART SINGLE");

    // Enable telemetry and age its firmware deadline so the 100 ms service
    // path can be verified without simulating ten million idle clocks.
    sw = 16'h2006;
    wait_clocks(1000);
    start = rx_count;
    dut.dm.mem[5] = dut.bus.timer.timer[31:0] - 32'd10000000;
    wait_clocks(8000);
    if (rx_count - start !== 24 || rx_bytes[start] !== "M" ||
        rx_bytes[start+1] !== "E" || rx_bytes[start+2] !== "A" ||
        rx_bytes[start+3] !== "2")
      $fatal(1, "telemetry MEA2 response mismatch bytes=%0d", rx_count-start);
    sw = 16'h0006;
    wait_clocks(1000);

    start = rx_count;
    uart_send(8'h6d);          // measure
    wait_clocks(8000);
    if (rx_count - start !== 24 || rx_bytes[start] !== "M" ||
        rx_bytes[start+1] !== "E" || rx_bytes[start+2] !== "A" ||
        rx_bytes[start+3] !== "2")
      $fatal(1, "measurement UART response mismatch bytes=%0d", rx_count-start);

    start = rx_count;
    uart_send(8'h64);          // stable packed dump
    wait_clocks(140000);
    if (rx_count - start !== 540 || rx_bytes[start] !== "C" ||
        rx_bytes[start+1] !== "A" || rx_bytes[start+2] !== "P" ||
        rx_bytes[start+3] !== "2")
      $fatal(1, "capture UART response mismatch bytes=%0d", rx_count-start);
    if (rx_bytes[start+6] !== 8'h00 || rx_bytes[start+7] !== 8'h10)
      $fatal(1, "capture sample count header mismatch");
    crc = 16'hffff;
    for (i = 0; i < 538; i = i + 1)
      crc = crc16_byte(crc, rx_bytes[start+i]);
    if (rx_bytes[start+538] !== crc[7:0] ||
        rx_bytes[start+539] !== crc[15:8])
      $fatal(1, "capture CRC mismatch got=%02x%02x expected=%04x",
          rx_bytes[start+539], rx_bytes[start+538], crc);

    start = rx_count;
    uart_send(8'h70);          // perf
    wait_clocks(12000);
    if (rx_count - start !== 40 || rx_bytes[start] !== "P" ||
        rx_bytes[start+1] !== "R" || rx_bytes[start+2] !== "F" ||
        rx_bytes[start+3] !== "2")
      $fatal(1, "perf UART response mismatch bytes=%0d", rx_count-start);

    loopback_enable = 1'b0;    // disconnect the simulated JA-to-JB1 jumper
    wait_clocks(8000);
    if (dut.bus.signal_present || dut.bus.edge_valid || !rgb1_r)
      $fatal(1, "no-signal timeout/status failed present=%b valid=%b rgb_r=%b age=%0d sw=%h cached_sw=%h pc=%h",
          dut.bus.signal_present, dut.bus.edge_valid, rgb1_r,
          dut.bus.edge_age, sw,
          dut.dm.mem[3], dut.cpu.pc);
    // Earlier UP presses intentionally started a one-second timebase pop-up.
    // Expire it here so this accelerated test observes the no-signal page.
    dut.dm.mem[12] = dut.bus.timer.timer[31:0] - 32'd100000000;
    dut.dm.mem[4] = dut.bus.timer.timer[31:0] - 32'd5000000;
    wait_clocks(8000);
    if (dut.bus.display.display_data0 !== 32'h1819161a ||
        dut.bus.display.display_data1 !== 32'h1f1f1617)
      $fatal(1, "no-signal display retained stale measurement data=%h_%h",
          dut.bus.display.display_data1, dut.bus.display.display_data0);

    $display("SOC REALTIME SCOPE PASS: frames=%0d frequency=%0d dump_crc=%04x",
        dut.bus.live_frame_counter, dut.bus.edge_frequency, crc);
    $finish;
  end
endmodule
