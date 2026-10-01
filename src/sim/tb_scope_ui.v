module tb_scope_ui;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [4:0] buttons = 5'd0;
  reg [15:0] switches = 16'd0;
  reg event_read = 1'b0;
  reg [3:0] button_off = 4'd0;
  wire [31:0] button_rdata;
  wire [4:0] button_state, button_event;
  wire [15:0] switch_state;
  reg display_we = 1'b0;
  reg [3:0] display_off = 4'd0;
  reg [31:0] display_wdata = 32'd0;
  wire [31:0] display_rdata;
  wire [7:0] an;
  wire [6:0] seg;
  wire dp;
  reg run = 1'b0, hold = 1'b0, single_armed = 1'b0, error = 1'b0;
  reg present = 1'b0, waiting = 1'b0, selftest = 1'b0, selftest_pass = 1'b0;
  wire r0, g0, b0, r1, g1, b1;
  always #5 clk = ~clk;

  button_mmio #(.DEBOUNCE_BITS(2)) buttons_dut (
      .clk(clk), .rst(rst), .btn_async(buttons), .sw_async(switches),
      .event_read(event_read), .button_state(button_state),
      .button_event(button_event), .switch_state(switch_state),
      .off(button_off), .rdata(button_rdata)
  );
  sevenseg display_dut (
      .clk(clk), .rst(rst), .we(display_we), .off(display_off),
      .wdata(display_wdata), .rdata(display_rdata), .an(an), .seg(seg), .dp(dp)
  );
  rgb_status rgb_dut (
      .run(run), .hold(hold), .single_armed(single_armed), .error(error),
      .signal_present(present), .waiting_trigger(waiting),
      .selftest(selftest), .selftest_pass(selftest_pass),
      .rgb0_r(r0), .rgb0_g(g0), .rgb0_b(b0),
      .rgb1_r(r1), .rgb1_g(g1), .rgb1_b(b1)
  );

  task clocks;
    input integer count;
    integer n;
    begin
      for (n = 0; n < count; n = n + 1) @(posedge clk);
    end
  endtask
  task display_write;
    input [3:0] a;
    input [31:0] d;
    begin
      @(negedge clk); display_off = a; display_wdata = d; display_we = 1'b1;
      @(negedge clk); display_we = 1'b0;
    end
  endtask

  initial begin
    clocks(3);
    rst = 1'b0;
    switches = 16'hd39a;
    clocks(4);
    button_off = 4'h8; #1;
    if (button_rdata[15:0] !== 16'hd39a)
      $fatal(1, "switch synchronization/mapping failed");

    buttons[0] = 1'b1;
    clocks(10);
    buttons[0] = 1'b0;
    clocks(10);
    if (!button_event[0]) $fatal(1, "debounced button event missing");
    @(negedge clk); event_read = 1'b1;
    @(negedge clk); event_read = 1'b0;
    clocks(2);
    if (button_event[0]) $fatal(1, "button event did not clear");

    display_write(4'h0, 32'h19181617); // i S n o glyph coverage
    display_write(4'h4, 32'h1e1d1c1b); // M k t u glyph coverage
    display_write(4'h8, 32'h00000055);
    display_write(4'hc, 32'd1);
    display_off = 4'h0; #1;
    if (display_rdata !== 32'h19181617)
      $fatal(1, "seven-segment register readback failed");

    run = 1'b1; #1;
    if ({r0,g0,b0} !== 3'b010) $fatal(1, "RUN RGB failed");
    hold = 1'b1; #1;
    if ({r0,g0,b0} !== 3'b001) $fatal(1, "HOLD RGB priority failed");
    single_armed = 1'b1; #1;
    if ({r0,g0,b0} !== 3'b110) $fatal(1, "SINGLE RGB priority failed");
    error = 1'b1; #1;
    if ({r0,g0,b0} !== 3'b100) $fatal(1, "ERROR RGB priority failed");

    present = 1'b0; #1;
    if ({r1,g1,b1} !== 3'b100) $fatal(1, "NO SIGNAL RGB failed");
    present = 1'b1; waiting = 1'b1; #1;
    if ({r1,g1,b1} !== 3'b110) $fatal(1, "WAIT RGB failed");
    waiting = 1'b0; #1;
    if ({r1,g1,b1} !== 3'b010) $fatal(1, "SIGNAL RGB failed");
    selftest = 1'b1; selftest_pass = 1'b0; #1;
    if ({r1,g1,b1} !== 3'b100) $fatal(1, "SELFTEST FAIL RGB failed");
    selftest_pass = 1'b1; #1;
    if ({r1,g1,b1} !== 3'b010) $fatal(1, "SELFTEST PASS RGB failed");

    $display("SCOPE UI PASS");
    $finish;
  end
endmodule
