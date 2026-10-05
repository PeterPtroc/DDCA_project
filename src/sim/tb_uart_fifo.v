`default_nettype none
module tb_uart_fifo;
  reg clk = 0, rst = 1, rx = 1, we = 0, re = 0;
  reg [3:0] off = 4;
  reg [31:0] wdata = 0;
  wire [31:0] rdata;
  wire rx_valid;
  integer i;
  uart_mmio #(.DIVIDER(16), .RX_FIFO_DEPTH(4)) dut (
      .clk(clk), .rst(rst), .rx(rx), .we(we), .re(re), .off(off),
      .wdata(wdata), .rdata(rdata), .tx(), .tx_ready(),
      .rx_valid(rx_valid), .activity()
  );
  always #5 clk = ~clk;
  task send_bit;
    input value;
    begin
      rx = value;
      repeat (16) @(negedge clk);
    end
  endtask
  task send_byte;
    input [7:0] value;
    integer bit_index;
    begin
      send_bit(0);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
        send_bit(value[bit_index]);
      send_bit(1);
    end
  endtask
  task pop_byte;
    input [7:0] expected;
    begin
      @(negedge clk);
      off = 8;
      re = 1;
      #1;
      if (!rx_valid || rdata != expected)
        $fatal(1, "FIFO ordering expected=%02x got=%08x", expected, rdata);
      @(negedge clk);
      re = 0;
      off = 4;
    end
  endtask
  initial begin
    repeat (6) @(negedge clk);
    rst = 0;
    for (i = 0; i < 4; i = i + 1) send_byte(8'h30 + i);
    #1;
    if (!rdata[3] || rdata[2]) $fatal(1, "FIFO full status mismatch");
    send_byte(8'hff);
    #1;
    if (!rdata[2]) $fatal(1, "FIFO overflow was not reported");
    // A full FIFO must preserve queued bytes when a new byte is dropped.
    pop_byte(8'h30);
    send_byte(8'h34);
    // Pop the oldest byte on the exact edge a new byte arrives at full capacity.
    fork
      send_byte(8'h35);
      begin
        @(posedge dut.received_strobe);
        @(negedge clk);
        off = 8;
        re = 1;
        #1;
        if (rdata != 8'h31) $fatal(1, "simultaneous pop data mismatch");
        @(negedge clk);
        re = 0;
        off = 4;
      end
    join
    pop_byte(8'h32);
    pop_byte(8'h33);
    pop_byte(8'h34);
    pop_byte(8'h35);
    if (rx_valid) $fatal(1, "FIFO not empty after drain");
    @(negedge clk);
    we = 1;
    wdata = 4;
    @(negedge clk);
    we = 0;
    #1;
    if (rdata[2]) $fatal(1, "overflow clear failed");
    $display("UART FIFO PASS: burst, ordering, wrap, full, overflow, simultaneous push/pop");
    $finish;
  end
endmodule
`default_nettype wire
