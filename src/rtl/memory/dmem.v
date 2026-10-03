`default_nettype none
module dmem (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [3:0] wstrb,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output reg [31:0] rdata
);
  // 64 KiB at 0x1000_0000. Firmware owns initialization (.data/.bss).
  // The byte lanes are independent so SB/SH do not require read-modify-write.
  (* ram_style = "block" *) reg [31:0] mem[0:16383];
  wire selected = (addr[31:16] == 16'h1000);
  wire [13:0] word_index = addr[15:2];
  // EX launches the request before this edge.  The registered BRAM result is
  // consumed by MEM/WB on the next edge, giving the path a full 10 ns cycle.
  always @(posedge clk) begin
    rdata <= selected ? mem[word_index] : 32'd0;
    if (we && selected) begin
      if (wstrb[0]) mem[word_index][7:0] <= wdata[7:0];
      if (wstrb[1]) mem[word_index][15:8] <= wdata[15:8];
      if (wstrb[2]) mem[word_index][23:16] <= wdata[23:16];
      if (wstrb[3]) mem[word_index][31:24] <= wdata[31:24];
    end
  end
  wire unused_rst = rst;
endmodule
`default_nettype wire
