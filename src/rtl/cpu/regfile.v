`default_nettype none
module regfile (
    input  wire        clk,
    input  wire        rst,
    input  wire [ 4:0] raddr1,
    input  wire [ 4:0] raddr2,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2,
    input  wire        we,
    input  wire [ 4:0] waddr,
    input  wire [31:0] wdata
);
  reg [31:0] regs[0:31];
  integer i;
  assign rdata1 = (raddr1 == 0) ? 32'd0 : ((we && waddr != 0 && waddr == raddr1) ? wdata : regs[raddr1]);
  assign rdata2 = (raddr2 == 0) ? 32'd0 : ((we && waddr != 0 && waddr == raddr2) ? wdata : regs[raddr2]);
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < 32; i = i + 1) regs[i] <= 32'd0;
    end else if (we && waddr != 0) begin
      regs[waddr] <= wdata;
    end
    regs[0] <= 32'd0;
  end
endmodule
`default_nettype wire
