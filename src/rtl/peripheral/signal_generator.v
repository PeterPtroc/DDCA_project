`default_nettype none

// One deterministic 100 MHz PWM output for JA1.
module signal_generator #(
    parameter CLOCK_HZ = 100000000
) (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [4:0] off,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output wire enabled,
    output wire signal_out,
    output wire [31:0] period_ticks,
    output wire [31:0] high_ticks
);
  reg enable;
  reg [31:0] period;
  reg [31:0] high;
  reg [31:0] count;
  wire [31:0] safe_period = (period < 2) ? 32'd2 : period;
  wire [31:0] safe_high = (high > safe_period) ? safe_period : high;

  assign enabled = enable;
  assign signal_out = enable && (count < safe_high);
  assign period_ticks = safe_period;
  assign high_ticks = safe_high;

  always @* begin
    case (off)
      5'h00: rdata = {31'd0, enable};
      5'h04: rdata = period;
      5'h08: rdata = high;
      5'h0c: rdata = {30'd0, enable, 1'b1};
      default: rdata = 32'd0;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      enable <= 1'b0;
      period <= 32'd1000;
      high <= 32'd300;
      count <= 32'd0;
    end else begin
      if (we) begin
        case (off)
          5'h00: enable <= wdata[0];
          5'h04: period <= (wdata < 2) ? 32'd2 : wdata;
          5'h08: high <= wdata;
          default: ;
        endcase
      end
      if (!enable) begin
        count <= 32'd0;
      end else if (count >= safe_period - 1'b1) begin
        count <= 32'd0;
      end else begin
        count <= count + 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
