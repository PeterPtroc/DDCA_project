`default_nettype none
module mmio_decoder #(
    parameter BUTTON_DEBOUNCE_BITS = 18,
    parameter UART_DIVIDER = 868,
    parameter EDGE_MIN_TIMEOUT_TICKS = 10000000,
    parameter EDGE_INITIAL_TIMEOUT_TICKS = 100000000,
    parameter LIVE_AUTO_TIMEOUT_SAMPLES = 1024
) (
    input wire clk,
    input wire rst,
    input wire valid,
    input wire we,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [15:0] sw,
    input wire [4:0] btn,
    input wire [7:0] capture_in,
    input wire uart_rx_i,
    input wire retire,
    input wire stall,
    input wire [1:0] fwd_ex,
    input wire [1:0] fwd_wb,
    input wire flush,
    input wire branch,
    input wire branch_taken,
    input wire crc,
    output wire [31:0] rdata,
    output wire [15:0] led,
    output wire [31:0] test_result,
    output wire uart_tx,
    output wire generator_out,
    output wire capture_armed,
    output wire capture_triggered,
    output wire capture_done,
    output wire [7:0] seg_an,
    output wire [6:0] seg,
    output wire seg_dp,
    output wire rgb0_r,
    output wire rgb0_g,
    output wire rgb0_b,
    output wire rgb1_r,
    output wire rgb1_g,
    output wire rgb1_b
);
  wire gpio_sel = addr[31:12] == 20'h40000;
  wire uart_sel = addr[31:12] == 20'h40001;
  wire timer_sel = addr[31:12] == 20'h40002;
  wire generator_sel = addr[31:12] == 20'h40003;
  wire cap_sel = addr[31:12] == 20'h40004;
  wire perf_sel = addr[31:12] == 20'h40006;
  wire button_sel = addr[31:12] == 20'h40007;
  wire display_sel = addr[31:12] == 20'h40008;
  wire edge_sel = addr[31:12] == 20'h40009;
  wire live_sel = addr[31:12] == 20'h40005;
  wire win_sel = addr[31:14] == 18'h10004;

  wire [31:0] gdata, udata, tdata, generator_data, cdata, perfdata;
  wire [31:0] button_data, display_data, edge_data, live_data;
  wire [15:0] gpio_led;
  wire uart_ready, uart_rx_valid, uart_activity;
  wire [12:0] capture_count;
  wire [11:0] capture_trigger_index;
  wire edge_valid, signal_present, edge_averaging;
  wire [31:0] edge_period, edge_high, edge_low, edge_frequency, edge_age;
  wire [15:0] live_frame;
  wire live_frame_valid, live_trigger_event, live_waiting, live_running;
  wire live_forced, live_single_done;
  wire [31:0] live_frame_counter;
  wire [1:0] live_mode;
  wire live_hold;
  wire [31:0] live_sample_div;
  wire live_edge;
  wire scope_signal;
  wire generator_enabled;
  wire [31:0] generator_period, generator_high;
  wire [15:0] switch_state;
  reg live_control_enable_reg;
  reg [1:0] live_mode_reg;
  reg live_hold_reg;
  reg live_edge_reg;
  reg [31:0] live_sample_div_reg;
  wire clear = valid && we && perf_sel && (addr[6:2] == 5'h09);

  input_sync #(.WIDTH(1)) scope_sync (
      .clk(clk), .rst(rst), .async_in(capture_in[0]), .sync_out(scope_signal)
  );
  gpio_mmio gpio (
      .clk(clk), .rst(rst), .we(valid && we && gpio_sel),
      .off(addr[3:0]), .wdata(wdata), .sw(sw), .btn(btn),
      .led(gpio_led), .test_result(test_result), .rdata(gdata)
  );
  uart_mmio #(.DIVIDER(UART_DIVIDER)) uart (
      .clk(clk), .rst(rst), .rx(uart_rx_i),
      .we(valid && we && uart_sel), .re(valid && !we && uart_sel),
      .off(addr[3:0]), .wdata(wdata), .rdata(udata), .tx(uart_tx),
      .tx_ready(uart_ready), .rx_valid(uart_rx_valid), .activity(uart_activity)
  );
  timer_mmio timer (.clk(clk), .rst(rst), .off(addr[2:0]), .rdata(tdata));
  signal_generator generator (
      .clk(clk), .rst(rst), .we(valid && we && generator_sel),
      .off(addr[4:0]), .wdata(wdata), .rdata(generator_data),
      .enabled(generator_enabled), .signal_out(generator_out),
      .period_ticks(generator_period), .high_ticks(generator_high)
  );
  scope_capture cap (
      .clk(clk), .rst(rst), .scope_signal(scope_signal),
      .we(valid && we && cap_sel), .off(addr[5:0]), .wdata(wdata),
      .window_sel(win_sel), .window_index(addr[13:2]),
      .rdata(cdata), .display_sample(),
      .armed(capture_armed),
      .triggered(capture_triggered), .done(capture_done), .count(capture_count),
      .trigger_index(capture_trigger_index)
  );
  perf_counter perf (
      .clk(clk), .rst(rst), .retire(retire), .stall(stall),
      .fwd_ex(fwd_ex), .fwd_wb(fwd_wb), .flush(flush), .branch(branch),
      .branch_taken(branch_taken), .crc(crc), .clear(clear),
      .off(addr[6:2]), .rdata(perfdata)
  );
  button_mmio #(.DEBOUNCE_BITS(BUTTON_DEBOUNCE_BITS)) buttons (
      .clk(clk), .rst(rst), .btn_async(btn), .sw_async(sw),
      .event_read(valid && !we && button_sel && addr[3:0] == 4'h4),
      .button_state(), .button_event(), .switch_state(switch_state),
      .off(addr[3:0]), .rdata(button_data)
  );
  sevenseg display (
      .clk(clk), .rst(rst), .we(valid && we && display_sel),
      .off(addr[3:0]), .wdata(wdata), .rdata(display_data),
      .an(seg_an), .seg(seg), .dp(seg_dp)
  );
  edge_meter_scope #(
      .MIN_TIMEOUT_TICKS(EDGE_MIN_TIMEOUT_TICKS),
      .INITIAL_TIMEOUT_TICKS(EDGE_INITIAL_TIMEOUT_TICKS)
  ) meter (
      .clk(clk), .rst(rst), .sample(scope_signal),
      .we(valid && we && edge_sel), .off(addr[4:0]), .wdata(wdata),
      .rdata(edge_data), .valid(edge_valid), .signal_present(signal_present),
      .averaging(edge_averaging), .period_ticks(edge_period),
      .high_ticks(edge_high), .low_ticks(edge_low), .frequency_hz(edge_frequency),
      .edge_age(edge_age)
  );
  live_scope #(.AUTO_TIMEOUT_SAMPLES(LIVE_AUTO_TIMEOUT_SAMPLES)) live (
      .clk(clk), .rst(rst), .scope_signal(scope_signal),
      .enable(live_control_enable), .hold(live_hold), .mode(live_mode),
      .trigger_edge(live_edge), .sample_div(live_sample_div),
      .wave_frame(live_frame), .frame_valid(live_frame_valid),
      .trigger_event(live_trigger_event), .waiting_trigger(live_waiting),
      .running(live_running), .auto_forced(live_forced),
      .single_done(live_single_done), .frame_counter(live_frame_counter)
  );
  wire live_control_enable;
  assign live_control_enable = live_control_enable_reg;
  assign live_hold = live_hold_reg;
  assign live_mode = live_mode_reg;
  assign live_edge = live_edge_reg;
  assign live_sample_div = live_sample_div_reg;
  assign led = live_frame;

  always @(posedge clk) begin
    if (rst) begin
      live_control_enable_reg <= 1'b0;
      live_hold_reg <= 1'b0;
      live_mode_reg <= 2'd0;
      live_edge_reg <= 1'b0;
      live_sample_div_reg <= 32'd1;
    end else if (valid && we && live_sel) begin
      case (addr[5:2])
        4'h0: begin
          live_control_enable_reg <= wdata[0];
          live_hold_reg <= wdata[1];
        end
        4'h2: live_mode_reg <= wdata[1:0];
        4'h3: live_edge_reg <= wdata[0];
        4'h4: live_sample_div_reg <= (wdata == 0) ? 32'd1 : wdata;
        default: ;
      endcase
    end
  end

  assign live_data =
      (addr[5:2] == 4'h0) ? {30'd0, live_hold, live_control_enable_reg} :
      (addr[5:2] == 4'h1) ? {27'd0, live_forced,
                              (live_single_done | live_trigger_event),
                              live_frame_valid, live_waiting, live_running} :
      (addr[5:2] == 4'h2) ? {30'd0, live_mode} :
      (addr[5:2] == 4'h3) ? {31'd0, live_edge} :
      (addr[5:2] == 4'h4) ? live_sample_div :
      (addr[5:2] == 4'h5) ? {16'd0, live_frame} :
      (addr[5:2] == 4'h6) ? live_frame_counter : 32'd0;

  wire [31:0] period_error = (edge_period >= generator_period) ?
      edge_period - generator_period : generator_period - edge_period;
  wire [31:0] high_error = (edge_high >= generator_high) ?
      edge_high - generator_high : generator_high - edge_high;
  wire selftest_active = switch_state[14] && generator_enabled;
  wire selftest_pass = edge_valid && signal_present &&
      period_error <= 32'd2 && high_error <= 32'd2;

  rgb_status status (
      .run(live_running), .hold(live_hold), .single_armed(live_mode == 2'd2 && !live_single_done),
      .error((test_result[31:16] == 16'hdead) ||
             (selftest_active && !selftest_pass)),
      .signal_present(signal_present),
      .waiting_trigger(live_waiting), .selftest(selftest_active),
      .selftest_pass(selftest_pass),
      .rgb0_r(rgb0_r), .rgb0_g(rgb0_g), .rgb0_b(rgb0_b),
      .rgb1_r(rgb1_r), .rgb1_g(rgb1_g), .rgb1_b(rgb1_b)
  );

  assign rdata = gpio_sel ? gdata : uart_sel ? udata : timer_sel ? tdata :
                 generator_sel ? generator_data : (cap_sel || win_sel) ? cdata :
                 perf_sel ? perfdata : button_sel ? button_data :
                 display_sel ? display_data : edge_sel ? edge_data :
                 live_sel ? live_data : 32'd0;
endmodule
`default_nettype wire
