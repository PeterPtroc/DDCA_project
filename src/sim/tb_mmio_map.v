module tb_mmio_map;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg valid = 1'b0;
  reg we = 1'b0;
  reg [31:0] addr = 32'd0;
  reg [31:0] wdata = 32'd0;
  wire [31:0] rdata;
  wire [15:0] led;
  wire [31:0] test_result;
  wire uart_tx;
  wire pwm_out;
  wire [7:0] capture_sample;
  wire capture_armed;
  wire capture_triggered;
  wire capture_done;

  always #5 clk = ~clk;

  mmio_decoder dut (
      .clk(clk),
      .rst(rst),
      .valid(valid),
      .we(we),
      .addr(addr),
      .wdata(wdata),
      .sw(16'd0),
      .btn(5'd0),
      .capture_in(8'd0),
      .uart_rx_i(1'b1),
      .display_index(12'd0),
      .retire(1'b0),
      .stall(1'b0),
      .fwd_ex(2'd0),
      .fwd_wb(2'd0),
      .flush(1'b0),
      .branch(1'b0),
      .branch_taken(1'b0),
      .crc(1'b0),
      .rdata(rdata),
      .led(led),
      .test_result(test_result),
      .uart_tx(uart_tx),
      .pwm_out(pwm_out),
      .pattern_out(),
      .pattern_enabled(),
      .capture_sample(capture_sample),
      .display_sample(),
      .capture_armed(capture_armed),
      .capture_triggered(capture_triggered),
      .capture_done(capture_done),
      .seg_an(),
      .seg(),
      .seg_dp()
  );

  task mmio_write;
    input [31:0] write_addr;
    input [31:0] write_data;
    begin
      @(negedge clk);
      addr = write_addr;
      wdata = write_data;
      valid = 1'b1;
      we = 1'b1;
      @(negedge clk);
      valid = 1'b0;
      we = 1'b0;
    end
  endtask

  task check_read;
    input [31:0] read_addr;
    input [31:0] expected;
    begin
      @(negedge clk);
      addr = read_addr;
      #1;
      if (rdata !== expected)
        $fatal(1, "MMIO read mismatch at %h: got %h expected %h", read_addr, rdata, expected);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;

    check_read(32'h40001004, 32'd1);
    check_read(32'h40004010, 32'd4096);
    check_read(32'h4000401c, 32'd1);
    check_read(32'h40004020, 32'd0);

    mmio_write(32'h40004010, 32'd5000);
    check_read(32'h40004010, 32'd4096);
    mmio_write(32'h40004010, 32'd0);
    check_read(32'h40004010, 32'd1);

    mmio_write(32'h40003004, 32'd8);
    mmio_write(32'h40003008, 32'd4);
    check_read(32'h40003004, 32'd8);
    check_read(32'h40003008, 32'd4);

    mmio_write(32'h4000401c, 32'd10);
    mmio_write(32'h40004020, 32'd2048);
    check_read(32'h4000401c, 32'd10);
    check_read(32'h40004020, 32'd2048);

    mmio_write(32'h40008000, 32'h03020100);
    mmio_write(32'h4000800c, 32'd1);
    check_read(32'h40008000, 32'h03020100);
    check_read(32'h4000800c, 32'd1);

    mmio_write(32'h4000a008, 32'd100);
    mmio_write(32'h4000a00c, 32'd30);
    mmio_write(32'h4000a000, 32'hff);
    check_read(32'h4000a008, 32'd100);
    check_read(32'h4000a00c, 32'd30);
    check_read(32'h4000a000, 32'hff);

    dut.cap.mem[0] = 8'ha5;
    dut.cap.mem[1024] = 8'h3c;
    dut.cap.mem[4095] = 8'h5a;
    check_read(32'h40010000, 32'h000000a5);
    check_read(32'h40011000, 32'h0000003c);
    check_read(32'h40013ffc, 32'h0000005a);
    check_read(32'h40005000, 32'd0);

    addr = 32'h40006000;
    #1;
    if (rdata === 32'd0) $fatal(1, "PERF base was not decoded independently");

    $display("MMIO MAP PASS: v1.0 peripherals and Capture DATA window");
    $finish;
  end
endmodule
