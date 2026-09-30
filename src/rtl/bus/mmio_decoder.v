`default_nettype none
module mmio_decoder (
    input wire clk,
    input wire rst,
    input wire valid,
    input wire we,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [15:0] sw,
    input wire [4:0] btn,
    input wire [7:0] capture_in,
    input wire retire,
    input wire stall,
    input wire [1:0] fwd_ex,
    fwd_wb,
    input wire flush,
    branch,
    branch_taken,
    crc,
    output wire [31:0] rdata,
    output wire [15:0] led,
    output wire [31:0] test_result,
    output wire uart_tx,
    output wire pwm_out,
    output wire [7:0] capture_sample,
    output wire capture_armed,
    capture_triggered,
    capture_done
);
  wire gpio_sel = addr[31:12] == 20'h40000;
  wire uart_sel = addr[31:12] == 20'h40001;
  wire timer_sel = addr[31:12] == 20'h40002;
  wire pwm_sel = addr[31:12] == 20'h40003;
  wire cap_sel = addr[31:12] == 20'h40004;
  wire win_sel = addr[31:14] == 18'h10004;
  wire perf_sel = addr[31:12] == 20'h40006;
  wire [31:0] gdata, tdata, pdata, cdata, perfdata, udata;
  wire uart_ready;
  wire [12:0] capture_count;
  wire [11:0] capture_trigger_index;
  wire uart_start = valid && we && uart_sel && (addr[3:0] == 4'h0) && uart_ready;
  wire clear = valid && we && perf_sel && (addr[5:2] == 4'h9);
  assign udata = (addr[3:0] == 4'h4) ? {31'd0, uart_ready} : 32'd0;
  gpio_mmio gpio (
      .clk(clk),
      .rst(rst),
      .we(valid && we && gpio_sel),
      .off(addr[3:0]),
      .wdata(wdata),
      .sw(sw),
      .btn(btn),
      .led(led),
      .test_result(test_result),
      .rdata(gdata)
  );
  uart_tx uart (
      .clk(clk),
      .rst(rst),
      .start(uart_start),
      .data(wdata[7:0]),
      .ready(uart_ready),
      .tx(uart_tx)
  );
  timer_mmio timer (
      .clk  (clk),
      .rst  (rst),
      .off  (addr[2:0]),
      .rdata(tdata)
  );
  pwm_mmio pwm (
      .clk(clk),
      .rst(rst),
      .we(valid && we && pwm_sel),
      .off(addr[3:0]),
      .wdata(wdata),
      .pwm_out(pwm_out),
      .rdata(pdata)
  );
  logic_capture cap (
      .clk(clk),
      .rst(rst),
      .capture_in(capture_in),
      .we(valid && we && cap_sel),
      .off(addr[4:0]),
      .wdata(wdata),
      .window_sel(win_sel),
      .window_index(addr[13:2]),
      .rdata(cdata),
      .sample_sync(capture_sample),
      .armed(capture_armed),
      .triggered(capture_triggered),
      .done(capture_done),
      .count(capture_count),
      .trigger_index(capture_trigger_index)
  );
  perf_counter perf (
      .clk(clk),
      .rst(rst),
      .retire(retire),
      .stall(stall),
      .fwd_ex(fwd_ex),
      .fwd_wb(fwd_wb),
      .flush(flush),
      .branch(branch),
      .branch_taken(branch_taken),
      .crc(crc),
      .clear(clear),
      .off(addr[6:2]),
      .rdata(perfdata)
  );
  assign rdata=gpio_sel?gdata:uart_sel?udata:timer_sel?tdata:pwm_sel?pdata:(cap_sel||win_sel)?cdata:perf_sel?perfdata:32'd0;
endmodule
`default_nettype wire
