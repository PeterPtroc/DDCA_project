`default_nettype none
// Common PtrocOS peripherals. Unassigned pages read zero and ignore writes.
module ptrocos_mmio #(
    parameter BUTTON_DEBOUNCE_BITS = 18,
    parameter UART_DIVIDER = 868
) (
    input wire clk, rst, valid, we,
    input wire [31:0] addr, wdata,
    input wire [15:0] sw,
    input wire [4:0] btn,
    input wire uart_rx_i,
    input wire retire, stall,
    input wire [1:0] fwd_ex, fwd_wb,
    input wire flush, branch, branch_taken, crc,
    output wire [31:0] rdata, test_result,
    output wire [15:0] led,
    output wire uart_tx,
    output wire [7:0] seg_an,
    output wire [6:0] seg,
    output wire seg_dp,
    output wire rgb0_r, rgb0_g, rgb0_b, rgb1_r, rgb1_g, rgb1_b
);
  wire gpio_sel = addr[31:12] == 20'h40000;
  wire uart_sel = addr[31:12] == 20'h40001;
  wire timer_sel = addr[31:12] == 20'h40002;
  wire perf_sel = addr[31:12] == 20'h40006;
  wire button_sel = addr[31:12] == 20'h40007;
  wire display_sel = addr[31:12] == 20'h40008;
  wire [31:0] gpio_data, uart_data, timer_data, perf_data, button_data, display_data;
  wire clear = valid && we && perf_sel && addr[6:2] == 5'h09;

  gpio_mmio gpio (
      .clk(clk), .rst(rst), .we(valid && we && gpio_sel),
      .off(addr[4:0]), .wdata(wdata), .sw(sw), .btn(btn),
      .led(led), .test_result(test_result), .rdata(gpio_data),
      .rgb({rgb1_b, rgb1_g, rgb1_r, rgb0_b, rgb0_g, rgb0_r})
  );
  uart_mmio #(.DIVIDER(UART_DIVIDER)) uart (
      .clk(clk), .rst(rst), .rx(uart_rx_i),
      .we(valid && we && uart_sel), .re(valid && !we && uart_sel),
      .off(addr[3:0]), .wdata(wdata), .rdata(uart_data), .tx(uart_tx),
      .tx_ready(), .rx_valid(), .activity()
  );
  timer_mmio timer (.clk(clk), .rst(rst), .off(addr[2:0]), .rdata(timer_data));
  perf_counter perf (
      .clk(clk), .rst(rst), .retire(retire), .stall(stall),
      .fwd_ex(fwd_ex), .fwd_wb(fwd_wb), .flush(flush), .branch(branch),
      .branch_taken(branch_taken), .crc(crc), .clear(clear),
      .off(addr[6:2]), .rdata(perf_data)
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
  assign rdata = gpio_sel ? gpio_data : uart_sel ? uart_data :
                 timer_sel ? timer_data : perf_sel ? perf_data :
                 button_sel ? button_data : display_sel ? display_data : 32'd0;
endmodule
`default_nettype wire
