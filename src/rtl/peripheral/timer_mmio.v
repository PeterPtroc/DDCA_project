`default_nettype none
module timer_mmio (
    input wire clk,
    input wire rst,
    input wire [2:0] off,
    output wire [31:0] rdata
);
  reg [63:0] timer;
  assign rdata = (off == 0) ? timer[31:0] : timer[63:32];
  always @(posedge clk)
    if (rst) timer <= 0;
    else timer <= timer + 1;
endmodule
`default_nettype wire
