`default_nettype none

module tb_scope_core;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  task clocks;
    input integer count;
    integer n;
    begin
      for (n = 0; n < count; n = n + 1) @(posedge clk);
    end
  endtask

  // Eight continuously running fixed Pmod JA test signals.
  reg fixed_rst = 1'b1;
  wire [7:0] fixed_out;

  fixed_test_signals fixed_signals_dut (
      .clk(clk), .rst(fixed_rst), .test_out(fixed_out)
  );

  task check_fixed_signal;
    input integer channel;
    input integer expected_period;
    input integer expected_high;
    integer sample_index;
    integer align_count;
    reg expected_level;
    begin
      // Align to a low-to-high wrap, then check every cycle of two periods.
      align_count = 0;
      while (fixed_out[channel] !== 1'b0 &&
             align_count <= expected_period) begin
        @(negedge clk);
        align_count = align_count + 1;
      end
      if (fixed_out[channel] !== 1'b0)
        $fatal(1, "JA channel %0d never went low", channel);
      while (fixed_out[channel] !== 1'b1 &&
             align_count <= (expected_period * 2 + 2)) begin
        @(negedge clk);
        align_count = align_count + 1;
      end
      if (fixed_out[channel] !== 1'b1)
        $fatal(1, "JA channel %0d never started a new period", channel);

      for (sample_index = 0; sample_index < expected_period * 2;
           sample_index = sample_index + 1) begin
        expected_level = ((sample_index % expected_period) < expected_high);
        if (fixed_out[channel] !== expected_level)
          $fatal(1, "JA channel %0d mismatch at cycle %0d: expected %b got %b",
              channel, sample_index, expected_level, fixed_out[channel]);
        @(negedge clk);
      end
      $display("FIXED JA%0d PASS: period=%0d high=%0d (two periods)",
          (channel < 4) ? channel + 1 : channel + 3,
          expected_period, expected_high);
    end
  endtask

  // Edge meter
  reg edge_rst = 1'b1;
  reg edge_sample = 1'b0;
  reg edge_we = 1'b0;
  reg [4:0] edge_off = 5'd0;
  reg [31:0] edge_wdata = 32'd0;
  wire [31:0] edge_rdata;
  wire [31:0] edge_period;
  wire [31:0] edge_high;
  wire [31:0] edge_age;
  wire edge_valid;
  wire edge_present;
  wire edge_averaging;

  edge_meter_scope #(
      .MIN_TIMEOUT_TICKS(100), .INITIAL_TIMEOUT_TICKS(40)
  ) edge_dut (
      .clk(clk), .rst(edge_rst), .sample(edge_sample), .we(edge_we),
      .off(edge_off), .wdata(edge_wdata), .rdata(edge_rdata),
      .valid(edge_valid), .signal_present(edge_present),
      .averaging(edge_averaging), .period_ticks(edge_period),
      .high_ticks(edge_high), .edge_age(edge_age)
  );

  task edge_level;
    input value;
    input integer count;
    integer n;
    begin
      @(negedge clk); edge_sample = value;
      for (n = 0; n < count; n = n + 1) @(posedge clk);
    end
  endtask

  // Live 16-sample scope
  reg live_rst = 1'b1;
  reg live_signal = 1'b0;
  reg live_enable = 1'b0;
  reg live_hold = 1'b0;
  reg [1:0] live_mode = 2'd3;
  reg live_edge = 1'b0;
  reg [31:0] live_sample_div = 32'd1;
  wire [15:0] live_frame;
  wire live_frame_valid;
  wire live_trigger_event;
  wire live_waiting;
  wire live_running;
  wire live_forced;
  wire live_single_done;
  wire [31:0] live_frame_counter;

  live_scope #(.AUTO_TIMEOUT_SAMPLES(8)) live_dut (
      .clk(clk), .rst(live_rst), .scope_signal(live_signal),
      .enable(live_enable), .hold(live_hold), .mode(live_mode),
      .trigger_edge(live_edge), .sample_div(live_sample_div),
      .wave_frame(live_frame), .frame_valid(live_frame_valid),
      .trigger_event(live_trigger_event), .waiting_trigger(live_waiting),
      .running(live_running), .auto_forced(live_forced),
      .single_done(live_single_done), .frame_counter(live_frame_counter)
  );

  task live_restart;
    begin
      @(negedge clk); live_enable = 1'b0;
      clocks(2);
      @(negedge clk); live_enable = 1'b1;
    end
  endtask

  // 4096-point deep capture
  reg capture_rst = 1'b1;
  reg capture_signal = 1'b0;
  reg capture_we = 1'b0;
  reg [5:0] capture_off = 6'd0;
  reg [31:0] capture_wdata = 32'd0;
  reg capture_window_sel = 1'b0;
  reg [11:0] capture_window_index = 12'd0;
  wire [31:0] capture_rdata;
  wire [7:0] capture_display_sample;
  wire capture_armed;
  wire capture_triggered;
  wire capture_done;
  wire [12:0] capture_count;
  wire [11:0] capture_trigger_index;

  scope_capture capture_dut (
      .clk(clk), .rst(capture_rst), .scope_signal(capture_signal),
      .we(capture_we), .off(capture_off), .wdata(capture_wdata),
      .window_sel(capture_window_sel), .window_index(capture_window_index),
      .rdata(capture_rdata), .display_sample(capture_display_sample),
      .armed(capture_armed), .triggered(capture_triggered),
      .done(capture_done), .count(capture_count),
      .trigger_index(capture_trigger_index)
  );

  task capture_write;
    input [5:0] address;
    input [31:0] data;
    begin
      @(negedge clk); capture_off = address; capture_wdata = data;
      capture_we = 1'b1;
      @(negedge clk); capture_we = 1'b0;
    end
  endtask

  // Basic UI: buttons, seven-segment registers and RGB status.
  reg ui_rst = 1'b1;
  reg [4:0] ui_buttons = 5'd0;
  reg [15:0] ui_switches = 16'd0;
  reg ui_event_read = 1'b0;
  reg [3:0] ui_button_off = 4'd0;
  wire [31:0] ui_button_rdata;
  wire [4:0] ui_button_state;
  wire [4:0] ui_button_event;
  wire [15:0] ui_switch_state;
  reg ui_display_we = 1'b0;
  reg [3:0] ui_display_off = 4'd0;
  reg [31:0] ui_display_wdata = 32'd0;
  wire [31:0] ui_display_rdata;
  wire [7:0] ui_an;
  wire [6:0] ui_seg;
  wire ui_dp;
  reg ui_run = 1'b0;
  reg ui_hold = 1'b0;
  reg ui_single_armed = 1'b0;
  reg ui_error = 1'b0;
  reg ui_present = 1'b0;
  reg ui_waiting = 1'b0;
  wire ui_r0, ui_g0, ui_b0, ui_r1, ui_g1, ui_b1;

  button_mmio #(.DEBOUNCE_BITS(2)) buttons_dut (
      .clk(clk), .rst(ui_rst), .btn_async(ui_buttons),
      .sw_async(ui_switches), .event_read(ui_event_read),
      .button_state(ui_button_state), .button_event(ui_button_event),
      .switch_state(ui_switch_state), .off(ui_button_off),
      .rdata(ui_button_rdata)
  );
  sevenseg display_dut (
      .clk(clk), .rst(ui_rst), .we(ui_display_we), .off(ui_display_off),
      .wdata(ui_display_wdata), .rdata(ui_display_rdata), .an(ui_an),
      .seg(ui_seg), .dp(ui_dp)
  );
  rgb_status rgb_dut (
      .run(ui_run), .hold(ui_hold), .single_armed(ui_single_armed),
      .error(ui_error), .signal_present(ui_present),
      .waiting_trigger(ui_waiting), .rgb0_r(ui_r0), .rgb0_g(ui_g0),
      .rgb0_b(ui_b0), .rgb1_r(ui_r1), .rgb1_g(ui_g1), .rgb1_b(ui_b1)
  );

  task display_write;
    input [3:0] address;
    input [31:0] data;
    begin
      @(negedge clk); ui_display_off = address; ui_display_wdata = data;
      ui_display_we = 1'b1;
      @(negedge clk); ui_display_we = 1'b0;
    end
  endtask

  integer i;
  reg [31:0] saved_frame_count;
  reg [11:0] saved_capture_ptr;

  initial begin
    clocks(3);
    fixed_rst = 1'b0;
    edge_rst = 1'b0;
    live_rst = 1'b0;
    capture_rst = 1'b0;
    ui_rst = 1'b0;

    // Each JA output must match two complete fixed periods and high times.
    check_fixed_signal(0, 100000, 20000);
    check_fixed_signal(1, 50000, 15000);
    check_fixed_signal(2, 20000, 8000);
    check_fixed_signal(3, 7021, 3511);
    check_fixed_signal(4, 5000, 3000);
    check_fixed_signal(5, 2000, 1400);
    check_fixed_signal(6, 1000, 800);
    check_fixed_signal(7, 500, 450);

    // Edge meter hardware: period/high plus no-signal timeout. Firmware
    // derives low/frequency in the SoC integration test.
    edge_level(1'b0, 3);
    edge_level(1'b1, 4);
    edge_level(1'b0, 6);
    edge_level(1'b1, 4);
    edge_level(1'b0, 6);
    clocks(40);
    #1;
    if (!edge_valid || !edge_present || edge_period !== 32'd10 ||
        edge_high !== 32'd4)
      $fatal(1, "edge meter mismatch valid=%b present=%b p=%0d h=%0d",
          edge_valid, edge_present, edge_period, edge_high);
    clocks(120);
    if (edge_valid || edge_present)
      $fatal(1, "edge meter no-signal timeout failed");

    // Live scope: FREE at div=2, HOLD/RUN, both trigger edges, AUTO and SINGLE.
    live_mode = 2'd3;
    live_sample_div = 32'd2;
    live_restart();
    for (i = 0; i < 32; i = i + 1) begin
      @(negedge clk); live_signal = (i % 4) < 2;
      @(posedge clk);
    end
    #1;
    if (live_frame_counter < 1 || live_frame === 16'd0 || !live_running)
      $fatal(1, "FREE/div=2 did not publish a frame");

    saved_frame_count = live_frame_counter;
    live_hold = 1'b1;
    clocks(80);
    if (live_frame_counter !== saved_frame_count || live_running)
      $fatal(1, "HOLD did not freeze live scope");
    live_hold = 1'b0;

    live_mode = 2'd1;
    live_edge = 1'b0;
    live_sample_div = 32'd1;
    live_signal = 1'b0;
    live_restart();
    saved_frame_count = live_frame_counter;
    clocks(20);
    if (live_frame_counter !== saved_frame_count || !live_waiting)
      $fatal(1, "NORMAL updated without a rising trigger");
    @(negedge clk); live_signal = 1'b1;
    clocks(12);
    if (live_frame_counter !== saved_frame_count + 1 ||
        live_frame[6] !== 1'b0 || live_frame[7] !== 1'b1)
      $fatal(1, "rising trigger alignment failed frame=%h", live_frame);

    live_edge = 1'b1;
    live_signal = 1'b1;
    live_restart();
    saved_frame_count = live_frame_counter;
    clocks(12);
    @(negedge clk); live_signal = 1'b0;
    clocks(12);
    if (live_frame_counter !== saved_frame_count + 1 ||
        live_frame[6] !== 1'b1 || live_frame[7] !== 1'b0)
      $fatal(1, "falling trigger alignment failed frame=%h", live_frame);

    live_mode = 2'd0;
    live_edge = 1'b0;
    live_signal = 1'b0;
    live_restart();
    saved_frame_count = live_frame_counter;
    clocks(12);
    if (live_frame_counter <= saved_frame_count)
      $fatal(1, "AUTO did not force a constant-signal frame");

    live_mode = 2'd2;
    live_signal = 1'b0;
    live_restart();
    saved_frame_count = live_frame_counter;
    clocks(5);
    @(negedge clk); live_signal = 1'b1;
    clocks(12);
    if (!live_single_done || live_frame_counter !== saved_frame_count + 1 ||
        live_running)
      $fatal(1, "SINGLE did not publish exactly one frame");
    for (i = 0; i < 40; i = i + 1) begin
      @(negedge clk); live_signal = ~live_signal;
      @(posedge clk);
    end
    if (live_frame_counter !== saved_frame_count + 1)
      $fatal(1, "SINGLE published more than one frame");

    // Deep capture: arm, rising trigger, 4096 samples and center trigger.
    capture_write(6'h08, 0);
    capture_write(6'h0c, 1);
    capture_write(6'h00, 1);
    for (i = 0; i < 2048; i = i + 1) begin
      capture_signal = 1'b0;
      @(posedge clk);
    end
    // Configuration changes while waiting for a trigger apply to the next
    // acquisition. This one must still trigger on rising at divider 1.
    capture_write(6'h08, 1);
    capture_write(6'h0c, 500);
    @(negedge clk); capture_signal = 1'b1; #1;
    @(posedge clk); #1;
    capture_signal = 1'b0;
    for (i = 0; i < 2048; i = i + 1) @(posedge clk);
    if (!capture_done || capture_count !== 13'd4096 ||
        capture_trigger_index !== 12'd2048)
      $fatal(1, "deep capture mismatch done=%b count=%0d trigger=%0d",
          capture_done, capture_count, capture_trigger_index);
    capture_off = 6'h24;
    #1;
    if (capture_rdata != 0) $fatal(1, "active trigger edge changed during capture");
    capture_off = 6'h28;
    #1;
    if (capture_rdata != 1) $fatal(1, "active sample divider changed during capture");
    capture_window_sel = 1'b1;
    capture_window_index = 12'd2047;
    #1;
    if (capture_display_sample[0] !== 1'b0)
      $fatal(1, "pre-trigger sample mismatch");
    capture_window_index = 12'd2048;
    #1;
    if (capture_display_sample[0] !== 1'b1)
      $fatal(1, "trigger sample missing at index 2048");

    // The next arm must pick up the new configuration.
    capture_window_sel = 0;
    capture_write(6'h00, 1);
    capture_off = 6'h24;
    #1;
    if (capture_rdata != 1) $fatal(1, "new capture did not latch falling edge");
    capture_off = 6'h28;
    #1;
    if (capture_rdata != 500) $fatal(1, "new capture did not latch divider 500");
    capture_write(6'h00, 2);

    // A cancel coincident with the last trigger sample must win over done.
    capture_write(6'h10, 3);
    capture_write(6'h20, 2);
    capture_write(6'h08, 0);
    capture_write(6'h0c, 1);
    capture_write(6'h00, 1);
    clocks(3);
    // A no-op control write must preserve the sampling interval.
    @(negedge clk);
    saved_capture_ptr = capture_dut.write_ptr;
    capture_off = 0;
    capture_wdata = 0;
    capture_we = 1;
    @(negedge clk);
    capture_we = 0;
    if (capture_dut.write_ptr != saved_capture_ptr + 12'd1)
      $fatal(1, "no-op control write dropped a capture sample");
    @(negedge clk);
    capture_signal = 1;
    capture_off = 0;
    capture_wdata = 2;
    capture_we = 1;
    @(negedge clk);
    capture_we = 0;
    if (capture_armed || capture_triggered || capture_done || capture_count != 0)
      $fatal(1, "same-cycle cancel/trigger did not clear capture state");

    // UI register/event behavior and the primary RUN/HOLD/SIGNAL states.
    ui_switches = 16'hd39a;
    clocks(4);
    ui_button_off = 4'h8;
    #1;
    if (ui_button_rdata[15:0] !== 16'hd39a)
      $fatal(1, "switch synchronization failed");
    ui_buttons[0] = 1'b1;
    clocks(10);
    ui_buttons[0] = 1'b0;
    clocks(10);
    if (!ui_button_event[0]) $fatal(1, "button event missing");
    @(negedge clk); ui_event_read = 1'b1;
    @(negedge clk); ui_event_read = 1'b0;
    clocks(2);
    if (ui_button_event[0]) $fatal(1, "button event did not clear");

    display_write(4'h0, 32'h19181617);
    display_write(4'h4, 32'h1e1d1c1b);
    display_write(4'h8, 32'h00000055);
    display_write(4'hc, 32'd1);
    ui_display_off = 4'h0;
    #1;
    if (ui_display_rdata !== 32'h19181617)
      $fatal(1, "seven-segment register write/read failed");

    ui_run = 1'b1;
    #1;
    if ({ui_r0,ui_g0,ui_b0} !== 3'b010) $fatal(1, "RUN RGB failed");
    ui_hold = 1'b1;
    #1;
    if ({ui_r0,ui_g0,ui_b0} !== 3'b001) $fatal(1, "HOLD RGB failed");
    ui_present = 1'b0;
    #1;
    if ({ui_r1,ui_g1,ui_b1} !== 3'b100) $fatal(1, "NO SIGNAL RGB failed");
    ui_present = 1'b1;
    #1;
    if ({ui_r1,ui_g1,ui_b1} !== 3'b010) $fatal(1, "SIGNAL RGB failed");

    $display("SCOPE CORE PASS");
    $finish;
  end
endmodule

`default_nettype wire
