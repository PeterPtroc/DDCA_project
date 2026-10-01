`default_nettype none
module button_debounce #(
    parameter COUNTER_BITS = 18
) (
    input wire clk,
    input wire rst,
    input wire noisy,
    output reg level,
    output reg pulse
);
  reg [COUNTER_BITS-1:0] counter;

  always @(posedge clk) begin
    if (rst) begin
      counter <= {COUNTER_BITS{1'b0}};
      level   <= 1'b0;
      pulse   <= 1'b0;
    end else begin
      pulse <= 1'b0;
      if (noisy == level) begin
        counter <= {COUNTER_BITS{1'b0}};
      end else if (&counter) begin
        level   <= noisy;
        pulse   <= noisy;
        counter <= {COUNTER_BITS{1'b0}};
      end else begin
        counter <= counter + 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
