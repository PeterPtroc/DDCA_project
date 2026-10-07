`default_nettype none
module gpio_mmio (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [4:0] off,
    input wire [31:0] wdata,
    input wire [15:0] sw,
    input wire [4:0] btn,
    output reg [15:0] led,
    output reg [31:0] test_result,
    output reg [5:0] rgb,
    output reg [31:0] rdata
);
  always @* begin
    case (off)
      5'h00: rdata = {16'd0, led};
      5'h04: rdata = {16'd0, sw};
      5'h08: rdata = {27'd0, btn};
      5'h0c: rdata = test_result;
      5'h10: rdata = {26'd0, rgb};
      default: rdata = 0;
    endcase
  end
  always @(posedge clk) begin
    if (rst) begin
      led <= 0;
      test_result <= 0;
      rgb <= 0;
    end else if (we) begin
      if (off == 0) led <= wdata[15:0];
      if (off == 5'h0c) test_result <= wdata;
      if (off == 5'h10) rgb <= wdata[5:0];
    end
  end
endmodule
`default_nettype wire
