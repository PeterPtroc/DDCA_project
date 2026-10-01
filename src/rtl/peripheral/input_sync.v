`default_nettype none
module input_sync #(
    parameter WIDTH = 1
) (
    input wire clk,
    input wire rst,
    input wire [WIDTH-1:0] async_in,
    output reg [WIDTH-1:0] sync_out
);
  (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_ff;

  always @(posedge clk) begin
    if (rst) begin
      sync_ff  <= {WIDTH{1'b0}};
      sync_out <= {WIDTH{1'b0}};
    end else begin
      sync_ff  <= async_in;
      sync_out <= sync_ff;
    end
  end
endmodule
`default_nettype wire
