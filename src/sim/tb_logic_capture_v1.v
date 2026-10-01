module tb_logic_capture_v1;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [7:0] capture_in = 8'd0;
  reg we = 1'b0;
  reg [5:0] off = 6'd0;
  reg [31:0] wdata = 32'd0;
  reg window_sel = 1'b0;
  reg [11:0] window_index = 12'd0;
  wire [31:0] rdata;
  wire [7:0] display_sample, sample_sync;
  wire armed, triggered, done;
  wire [12:0] count;
  wire [11:0] trigger_index;
  always #5 clk = ~clk;

  logic_capture dut (
      .clk(clk), .rst(rst), .capture_in(capture_in), .we(we), .off(off),
      .wdata(wdata), .window_sel(window_sel), .window_index(window_index),
      .display_index(12'd4), .rdata(rdata), .display_sample(display_sample),
      .sample_sync(sample_sync), .armed(armed), .triggered(triggered),
      .done(done), .count(count), .trigger_index(trigger_index)
  );

  task write_reg;
    input [5:0] write_off;
    input [31:0] write_data;
    begin
      @(negedge clk); off = write_off; wdata = write_data; we = 1'b1;
      @(negedge clk); we = 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    write_reg(6'h10, 32'd8);
    write_reg(6'h1c, 32'd2);
    write_reg(6'h20, 32'd4);
    write_reg(6'h08, 32'd0);
    write_reg(6'h0c, 32'd0);
    write_reg(6'h00, 32'd1);
    repeat (14) @(posedge clk);
    capture_in[0] = 1'b1;
    repeat (8) @(posedge clk);
    capture_in[0] = 1'b0;
    repeat (8) @(posedge clk);
    if (!done || count !== 13'd8 || trigger_index !== 12'd4)
      $fatal(1, "pre-trigger capture failed: done=%b count=%0d trigger=%0d",
             done, count, trigger_index);
    window_sel = 1'b1;
    window_index = 12'd4;
    #1;
    if (rdata[0] !== 1'b1 || display_sample[0] !== 1'b1)
      $fatal(1, "chronological trigger sample mapping failed");
    $display("LOGIC CAPTURE V1 PASS");
    $finish;
  end
endmodule
