`timescale 1ns/1ps
module tb_ptrocos_mmio;
  reg clk = 0;
  always #5 clk = !clk;
  reg rst = 1, valid = 0, we = 0;
  reg [31:0] addr = 0, wdata = 0;
  reg [15:0] sw = 16'ha55a;
  reg [4:0] btn = 0;
  reg rx = 1, retire = 0;
  wire [31:0] rdata, result;
  wire [15:0] led;
  wire [5:0] rgb;
  wire tx;
  wire [7:0] an;
  wire [6:0] seg;
  wire dp;
  ptrocos_mmio #(.BUTTON_DEBOUNCE_BITS(2), .UART_DIVIDER(8)) dut (
      .clk(clk), .rst(rst), .valid(valid), .we(we), .addr(addr), .wdata(wdata),
      .sw(sw), .btn(btn), .uart_rx_i(rx), .retire(retire), .stall(1'b0),
      .fwd_ex(2'd0), .fwd_wb(2'd0), .flush(1'b0), .branch(1'b0),
      .branch_taken(1'b0), .crc(1'b0), .rdata(rdata), .test_result(result),
      .led(led), .uart_tx(tx), .seg_an(an), .seg(seg), .seg_dp(dp),
      .rgb0_r(rgb[0]), .rgb0_g(rgb[1]), .rgb0_b(rgb[2]),
      .rgb1_r(rgb[3]), .rgb1_g(rgb[4]), .rgb1_b(rgb[5])
  );
  task write_word;
    input [31:0] address, value;
    begin
      @(negedge clk); addr = address; wdata = value; valid = 1; we = 1;
      @(negedge clk); valid = 0; we = 0;
    end
  endtask
  task read_word;
    input [31:0] address, expected;
    begin
      @(negedge clk); addr = address; valid = 1; we = 0;
      #1;
      if (rdata !== expected) $fatal(1, "MMIO %h: got %h expected %h", address, rdata, expected);
      @(negedge clk); valid = 0;
    end
  endtask
  task send_byte;
    input [7:0] value;
    integer bit_index;
    begin
      @(negedge clk); rx = 0;
      repeat (8) @(negedge clk);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        rx = value[bit_index]; repeat (8) @(negedge clk);
      end
      rx = 1; repeat (16) @(negedge clk);
    end
  endtask
  integer page;
  initial begin
    repeat (4) @(negedge clk); rst = 0;
    repeat (12) @(negedge clk);
    if (rgb !== 0 || led !== 0 || an !== 8'hff) $fatal(1, "reset outputs");
    read_word(32'h40000004, 32'ha55a);
    write_word(32'h40000000, 32'h12345678);
    write_word(32'h4000000c, 32'h01234567);
    write_word(32'h40000010, 32'hffffff2a);
    read_word(32'h40000010, 32'h2a);
    if (rgb !== 6'h2a || led !== 16'h5678) $fatal(1, "independent RGB/LED outputs");
    write_word(32'h40008000, 32'h01020304);
    write_word(32'h4000800c, 1);
    btn = 5'b00101;
    repeat (16) @(negedge clk);
    read_word(32'h40007000, 5);
    send_byte(8'h45);
    read_word(32'h40001004, 3);
    // Retired analyzer pages must be inert even with pending input events.
    for (page = 0; page < 3; page = page + 1) begin
      addr = page == 0 ? 32'h40004000 : page == 1 ? 32'h40005000 : 32'h40009000;
      write_word(addr, 32'hffffffff);
      read_word(addr + 4, 0);
    end
    write_word(32'h40010000, 32'hffffffff);
    read_word(32'h40010000, 0);
    read_word(32'h40000000, 32'h5678);
    read_word(32'h4000000c, 32'h01234567);
    read_word(32'h40000010, 32'h2a);
    read_word(32'h40008000, 32'h01020304);
    read_word(32'h4000800c, 1);
    read_word(32'h40007004, 5);
    read_word(32'h40007004, 0);
    read_word(32'h40001004, 3);
    read_word(32'h40001008, 32'h45);
    read_word(32'h40001004, 1);
    // A request without valid cannot change GPIO or clear performance counters.
    @(negedge clk); addr = 32'h40000010; wdata = 0; we = 1;
    @(negedge clk); we = 0;
    read_word(32'h40000010, 32'h2a);
    write_word(32'h40006024, 1);
    @(negedge clk); retire = 1;
    repeat (3) @(negedge clk); retire = 0;
    read_word(32'h40006004, 3);
    @(negedge clk); addr = 32'h40006024; we = 1;
    @(negedge clk); we = 0;
    read_word(32'h40006004, 3);
    write_word(32'h40006024, 1);
    read_word(32'h40006004, 0);
    @(negedge clk); rst = 1;
    repeat (2) @(negedge clk);
    if (rgb !== 0 || led !== 0 || result !== 0 || an !== 8'hff) $fatal(1, "reset after activity");
    $display("PTROCOS MMIO PASS: retired pages inert, GPIO/RGB, display, button events, UART FIFO and perf clear");
    $finish;
  end
  initial begin
    #100000; $fatal(1, "MMIO timeout");
  end
endmodule
