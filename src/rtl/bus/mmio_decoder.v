`default_nettype none
module mmio_decoder #(
    parameter BUTTON_DEBOUNCE_BITS = 18
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
    input wire [11:0] display_index,
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
    output wire pwm_out,
    output wire [7:0] pattern_out,
    output wire pattern_enabled,
    output wire [7:0] capture_sample,
    output wire [7:0] display_sample,
    output wire capture_armed,
    output wire capture_triggered,
    output wire capture_done,
    output wire [7:0] seg_an,
    output wire [6:0] seg,
    output wire seg_dp
);
  wire gpio_sel = addr[31:12] == 20'h40000;
  wire uart_sel = addr[31:12] == 20'h40001;
  wire timer_sel = addr[31:12] == 20'h40002;
  wire pwm_sel = addr[31:12] == 20'h40003;
  wire cap_sel = addr[31:12] == 20'h40004;
  wire perf_sel = addr[31:12] == 20'h40006;
  wire button_sel = addr[31:12] == 20'h40007;
  wire display_sel = addr[31:12] == 20'h40008;
  wire edge_sel = addr[31:12] == 20'h40009;
  wire pattern_sel = addr[31:12] == 20'h4000a;
  wire win_sel = addr[31:14] == 18'h10004;

  wire [31:0] gdata, udata, tdata, pdata, cdata, perfdata;
  wire [31:0] button_data, display_data, edge_data, pattern_data;
  wire [15:0] gpio_led;
  wire uart_ready, uart_rx_valid, uart_activity;
  wire [12:0] capture_count;
  wire [11:0] capture_trigger_index;
  wire edge_valid;
  wire [31:0] edge_period, edge_high, edge_frequency;
  wire clear = valid && we && perf_sel && (addr[6:2] == 5'h09);

  gpio_mmio gpio (
      .clk(clk), .rst(rst), .we(valid && we && gpio_sel),
      .off(addr[3:0]), .wdata(wdata), .sw(sw), .btn(btn),
      .led(gpio_led), .test_result(test_result), .rdata(gdata)
  );
  uart_mmio uart (
      .clk(clk), .rst(rst), .rx(uart_rx_i),
      .we(valid && we && uart_sel), .re(valid && !we && uart_sel),
      .off(addr[3:0]), .wdata(wdata), .rdata(udata), .tx(uart_tx),
      .tx_ready(uart_ready), .rx_valid(uart_rx_valid), .activity(uart_activity)
  );
  timer_mmio timer (.clk(clk), .rst(rst), .off(addr[2:0]), .rdata(tdata));
  pwm_mmio pwm (
      .clk(clk), .rst(rst), .we(valid && we && pwm_sel),
      .off(addr[3:0]), .wdata(wdata), .pwm_out(pwm_out), .rdata(pdata)
  );
  logic_capture cap (
      .clk(clk), .rst(rst), .capture_in(capture_in),
      .we(valid && we && cap_sel), .off(addr[5:0]), .wdata(wdata),
      .window_sel(win_sel), .window_index(addr[13:2]),
      .display_index(display_index), .rdata(cdata), .display_sample(display_sample),
      .sample_sync(capture_sample), .armed(capture_armed),
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
      .button_state(), .button_event(), .switch_state(),
      .off(addr[3:0]), .rdata(button_data)
  );
  sevenseg display (
      .clk(clk), .rst(rst), .we(valid && we && display_sel),
      .off(addr[3:0]), .wdata(wdata), .rdata(display_data),
      .an(seg_an), .seg(seg), .dp(seg_dp)
  );
  edge_meter meter (
      .clk(clk), .rst(rst), .sample(capture_sample),
      .we(valid && we && edge_sel), .off(addr[3:0]), .wdata(wdata),
      .rdata(edge_data), .valid(edge_valid), .period_ticks(edge_period),
      .high_ticks(edge_high), .frequency_hz(edge_frequency)
  );
  pattern_generator generator (
      .clk(clk), .rst(rst), .we(valid && we && pattern_sel),
      .off(addr[4:0]), .wdata(wdata), .rdata(pattern_data),
      .enabled(pattern_enabled), .pattern_out(pattern_out)
  );

  assign led[7:0] = capture_sample;
  assign led[8] = capture_armed;
  assign led[9] = capture_triggered;
  assign led[10] = capture_done;
  assign led[11] = uart_activity;
  assign led[12] = pattern_enabled;
  assign led[13] = 1'b1;
  assign led[14] = test_result == 32'h600d600d;
  assign led[15] = test_result[31:16] == 16'hdead;

  assign rdata = gpio_sel ? gdata : uart_sel ? udata : timer_sel ? tdata :
                 pwm_sel ? pdata : (cap_sel || win_sel) ? cdata :
                 perf_sel ? perfdata : button_sel ? button_data :
                 display_sel ? display_data : edge_sel ? edge_data :
                 pattern_sel ? pattern_data : 32'd0;
endmodule
`default_nettype wire
