module tb_analyzer_peripherals;
  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  reg [4:0] buttons = 5'd0;
  reg [15:0] switches = 16'h1234;
  reg button_read = 1'b0;
  reg [3:0] button_off = 4'd0;
  wire [31:0] button_rdata;
  button_mmio #(.DEBOUNCE_BITS(2)) button_dut (
      .clk(clk), .rst(rst), .btn_async(buttons), .sw_async(switches),
      .event_read(button_read), .button_state(), .button_event(),
      .switch_state(), .off(button_off), .rdata(button_rdata)
  );

  reg [7:0] meter_sample = 8'd0;
  reg meter_we = 1'b0;
  reg [3:0] meter_off = 4'd0;
  reg [31:0] meter_wdata = 32'd0;
  wire [31:0] meter_rdata, meter_period, meter_high, meter_frequency;
  wire meter_valid;
  edge_meter meter_dut (
      .clk(clk), .rst(rst), .sample(meter_sample), .we(meter_we),
      .off(meter_off), .wdata(meter_wdata), .rdata(meter_rdata),
      .valid(meter_valid), .period_ticks(meter_period),
      .high_ticks(meter_high), .frequency_hz(meter_frequency)
  );

  reg gen_we = 1'b0;
  reg [4:0] gen_off = 5'd0;
  reg [31:0] gen_wdata = 32'd0;
  wire [31:0] gen_rdata;
  wire gen_enabled;
  wire [7:0] pattern;
  pattern_generator generator_dut (
      .clk(clk), .rst(rst), .we(gen_we), .off(gen_off), .wdata(gen_wdata),
      .rdata(gen_rdata), .enabled(gen_enabled), .pattern_out(pattern)
  );

  reg uart_line = 1'b1;
  wire [7:0] uart_data;
  wire uart_valid;
  uart_rx #(.DIVIDER(16)) uart_dut (
      .clk(clk), .rst(rst), .rx(uart_line), .data(uart_data), .valid(uart_valid)
  );

  task gen_write;
    input [4:0] write_off;
    input [31:0] write_data;
    begin
      @(negedge clk); gen_off = write_off; gen_wdata = write_data; gen_we = 1'b1;
      @(negedge clk); gen_we = 1'b0;
    end
  endtask

  task meter_level;
    input value;
    input integer clocks;
    integer n;
    begin
      @(negedge clk); meter_sample[0] = value;
      for (n = 0; n < clocks; n = n + 1) @(posedge clk);
    end
  endtask

  task uart_bit;
    input value;
    integer n;
    begin
      uart_line = value;
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

  initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;

    buttons[0] = 1'b1;
    repeat (10) @(posedge clk);
    button_off = 4'h0; #1;
    if (button_rdata[0] !== 1'b1) $fatal(1, "button debounce state failed");
    button_off = 4'h4; #1;
    if (button_rdata[0] !== 1'b1) $fatal(1, "button event failed");
    @(negedge clk); button_read = 1'b1;
    @(negedge clk); button_read = 1'b0;
    @(posedge clk); #1;
    if (button_rdata[0] !== 1'b0) $fatal(1, "button event clear failed");

    gen_write(5'h08, 32'd8);
    gen_write(5'h0c, 32'd3);
    gen_write(5'h10, 32'h000000f8);
    gen_write(5'h00, 32'h00000007);
    if (!gen_enabled || pattern[7:3] !== 5'h1f)
      $fatal(1, "pattern generator enable/constant channels failed");
    repeat (10) @(posedge clk);
    if (generator_dut.period !== 32'd8 || generator_dut.high !== 32'd3)
      $fatal(1, "pattern generator configuration failed");

    meter_level(1'b0, 3);
    meter_level(1'b1, 4);
    meter_level(1'b0, 6);
    meter_level(1'b1, 4);
    #1;
    if (!meter_valid || meter_period !== 32'd10 || meter_high !== 32'd4)
      $fatal(1, "edge meter failed: valid=%b period=%0d high=%0d",
             meter_valid, meter_period, meter_high);

    uart_send(8'h55);
    repeat (4) @(posedge clk);
    if (uart_data !== 8'h55) $fatal(1, "UART RX failed: %h", uart_data);

    $display("ANALYZER PERIPHERALS PASS");
    $finish;
  end
endmodule
