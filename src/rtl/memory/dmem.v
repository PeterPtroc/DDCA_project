`default_nettype none
module dmem (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output wire [31:0] rdata
);
  // Synthesis note: the original reset branch cleared all 1024 words in a
  // for-loop. That reset requirement prevented RAM inference and expanded this
  // array into flip-flops. The asynchronous read port maps naturally to LUTRAM,
  // so memory contents are intentionally undefined after reset and firmware
  // must write a location before depending on its value.
  (* ram_style = "distributed" *) reg [31:0] mem[0:1023];
  assign rdata = (addr[31:12] == 20'h10000) ? mem[addr[11:2]] : 32'd0;
  always @(posedge clk) begin
    if (we && addr[31:12] == 20'h10000) begin
      mem[addr[11:2]] <= wdata;
    end
  end
endmodule
`default_nettype wire
