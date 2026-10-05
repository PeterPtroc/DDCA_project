`default_nettype none
module tb_freertos_display;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [15:0] switches = 16'h8006; // FREE mode with performance pages enabled
  reg [4:0] buttons = 5'd0;
  reg [2:0] test_select = 3'd6; // JA9 -> JB1
  reg [31:0] counter_value = 0;
  wire [7:0] fixed_out;
  wire [7:0] an;
  wire [6:0] seg;
  wire dp;
  integer cycles = 0;

  always #5 clk = ~clk;
  always @(posedge clk) begin
    cycles <= cycles + 1;
    if (cycles > 30000000) $fatal(1, "FreeRTOS display test timeout");
    if (!rst && dut.cpu.trap_taken && dut.cpu.trap_cause != 32'd11 &&
        dut.cpu.trap_cause != 32'h80000007)
      $fatal(1, "unexpected display-test trap cause=%08x", dut.cpu.trap_cause);
    if (!rst && dut.test_result[31:16] == 16'hdead)
      $fatal(1, "display-test firmware failure=%08x", dut.test_result);
  end

  fixed_test_signals fixed_signals (
      .clk(clk), .rst(rst), .test_out(fixed_out)
  );
  soc_top #(
      .BUTTON_DEBOUNCE_BITS(2), .UART_DIVIDER(16),
      .EDGE_MIN_TIMEOUT_TICKS(30000), .EDGE_INITIAL_TIMEOUT_TICKS(40000)
  ) dut (
      .clk(clk), .rst(rst), .sw(switches), .btn(buttons),
      .capture_in({7'd0, fixed_out[test_select]}), .uart_rx(1'b1),
      .led(), .uart_tx(), .seg_an(an), .seg(seg), .seg_dp(dp),
      .rgb0_r(), .rgb0_g(), .rgb0_b(), .rgb1_r(), .rgb1_g(), .rgb1_b()
  );

  function [6:0] expected_segments;
    input [7:0] character;
    begin
      case (character)
        "0": expected_segments = 7'b1000000;
        "1": expected_segments = 7'b1111001;
        "2": expected_segments = 7'b0100100;
        "3": expected_segments = 7'b0110000;
        "4": expected_segments = 7'b0011001;
        "5": expected_segments = 7'b0010010;
        "6": expected_segments = 7'b0000010;
        "7": expected_segments = 7'b1111000;
        "8": expected_segments = 7'b0000000;
        "9": expected_segments = 7'b0010000;
        "-": expected_segments = 7'b0111111;
        default: expected_segments = 7'bxxxxxxx;
      endcase
    end
  endfunction

  // Wait for a fresh complete firmware update, then check all eight physical
  // digit outputs. Expected text is independent of the firmware's conversion.
  task expect_display;
    input [63:0] text;
    reg [63:0] packed_codes;
    reg [7:0] character;
    reg [7:0] seen;
    integer n;
    integer position;
    begin
      for (position = 0; position < 8; position = position + 1) begin
        character = text[position*8 +: 8];
        packed_codes[position*8 +: 8] = (character == "-") ? 8'h10 : character - "0";
      end
      n = 0;
      while (!(dut.dv && dut.dwe && dut.da == 32'h4000800c &&
               dut.bus.display.display_data0 === packed_codes[31:0] &&
               dut.bus.display.display_data1 === packed_codes[63:32]) && n < 2000000) begin
        @(negedge clk);
        n = n + 1;
      end
      if (n == 2000000)
        $fatal(1, "expected display %s got codes=%h_%h", text,
               dut.bus.display.display_data1, dut.bus.display.display_data0);
      buttons = 0;
      seen = 0;
      n = 0;
      while (seen != 8'hff && n < 131073) begin
        @(negedge clk);
        position = dut.bus.display.digit;
        if (an !== ~(8'b1 << position) || dp !== 1'b1 ||
            seg !== expected_segments(text[position*8 +: 8]))
          $fatal(1, "physical display mismatch text=%s digit=%0d seg=%b an=%b dp=%b",
                 text, position, seg, an, dp);
        seen[position] = 1'b1;
        n = n + 1;
      end
      if (seen != 8'hff) $fatal(1, "display did not scan all digits");
      $display("DECIMAL DISPLAY PASS: %s", text);
    end
  endtask

  task next_page;
    input [63:0] text;
    begin
      @(negedge clk); buttons = 5'b01000;
      expect_display(text);
    end
  endtask

  initial begin
    repeat (10) @(negedge clk);
    rst = 0;
    expect_display("00100000"); // JA9 frequency: 100000 Hz
    test_select = 3'd3;
    expect_display("00014242"); // JA4 frequency: floor(100 MHz / 7021)
    test_select = 3'd6;
    expect_display("00100000");
    next_page("00001000");     // period ticks
    next_page("00000800");     // high ticks
    next_page("00000200");     // low ticks
    next_page("00007999");     // existing fixed-point duty calculation
    next_page("00000003");     // valid and signal-present status bits

    // Inject counter values at the peripheral boundary. The production CPU,
    // RTOS UI task, decimal conversion and display scanner remain active.
    force dut.bus.perf.cycle = counter_value;
    next_page("00000000");
    counter_value = 9;
    expect_display("00000009");
    counter_value = 10;
    expect_display("00000010");
    counter_value = 12345678;
    expect_display("12345678");
    counter_value = 99999999;
    expect_display("99999999");
    counter_value = 100000000;
    expect_display("--------");
    counter_value = 32'hffffffff;
    expect_display("--------");
    release dut.bus.perf.cycle;
    $display("FREERTOS DISPLAY PASS: JA4/JA9, all measurement pages, decimal boundaries, physical segment scan");
    $finish;
  end
endmodule
`default_nettype wire
