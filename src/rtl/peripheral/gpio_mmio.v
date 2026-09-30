`default_nettype none
module gpio_mmio (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [3:0] off,
    input wire [31:0] wdata,
    input wire [15:0] sw,
    input wire [4:0] btn,
    output reg [15:0] led,
    output reg [31:0] test_result,
    output reg [31:0] rdata
);
  always @* begin
    case (off)
      4'h0: rdata = {16'd0, led};
      4'h4: rdata = {16'd0, sw};
      4'h8: rdata = {27'd0, btn};
      4'hc: rdata = test_result;
      default: rdata = 0;
    endcase
  end
  always @(posedge clk) begin
    if (rst) begin
      led <= 0;
      test_result <= 0;
    end else if (we) begin
      if (off == 0) led <= wdata[15:0];
      if (off == 4'hc) test_result <= wdata;
    end
  end
endmodule
`default_nettype wire
