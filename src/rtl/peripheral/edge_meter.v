`default_nettype none
module edge_meter #(
    parameter CLOCK_HZ = 100000000
) (
    input wire clk,
    input wire rst,
    input wire [7:0] sample,
    input wire we,
    input wire [3:0] off,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output reg valid,
    output reg [31:0] period_ticks,
    output reg [31:0] high_ticks,
    output reg [31:0] frequency_hz
);
  reg enable;
  reg [2:0] channel;
  reg prev;
  reg have_rise;
  reg have_fall;
  reg [31:0] ticks;
  reg [31:0] rise_timestamp;
  reg [31:0] fall_timestamp;
  reg dividing;
  reg [5:0] divide_count;
  reg [31:0] divide_divisor;
  reg [31:0] divide_quotient;
  reg [32:0] divide_remainder;
  wire selected = sample[channel];
  wire rise = !prev && selected;
  wire fall = prev && !selected;
  wire [32:0] shifted_remainder = {divide_remainder[31:0], divide_quotient[31]};
  wire subtract_divisor = shifted_remainder >= {1'b0, divide_divisor};
  wire [32:0] next_remainder = subtract_divisor ?
      shifted_remainder - {1'b0, divide_divisor} : shifted_remainder;
  wire [31:0] next_quotient = {divide_quotient[30:0], subtract_divisor};

  always @* begin
    case (off)
      4'h0: rdata = {21'd0, channel, 6'd0, enable, valid};
      4'h4: rdata = period_ticks;
      4'h8: rdata = high_ticks;
      4'hc: rdata = frequency_hz;
      default: rdata = 32'd0;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      enable <= 1'b1;
      channel <= 3'd0;
      prev <= 1'b0;
      have_rise <= 1'b0;
      have_fall <= 1'b0;
      ticks <= 32'd0;
      rise_timestamp <= 32'd0;
      fall_timestamp <= 32'd0;
      valid <= 1'b0;
      period_ticks <= 32'd0;
      high_ticks <= 32'd0;
      frequency_hz <= 32'd0;
      dividing <= 1'b0;
      divide_count <= 6'd0;
      divide_divisor <= 32'd1;
      divide_quotient <= 32'd0;
      divide_remainder <= 33'd0;
    end else begin
      ticks <= ticks + 1'b1;
      prev <= selected;
      if (we && off == 4'h0) begin
        enable <= wdata[0];
        channel <= wdata[10:8];
        if (wdata[1]) begin
          valid <= 1'b0;
          have_rise <= 1'b0;
          have_fall <= 1'b0;
        end
      end
      if (enable) begin
        if (rise) begin
          if (have_rise) begin
            period_ticks <= ticks - rise_timestamp;
            if (have_fall) high_ticks <= fall_timestamp - rise_timestamp;
            if (ticks != rise_timestamp && !dividing) begin
              dividing <= 1'b1;
              divide_count <= 6'd0;
              divide_divisor <= ticks - rise_timestamp;
              divide_quotient <= CLOCK_HZ;
              divide_remainder <= 33'd0;
            end
            valid <= have_fall;
          end
          rise_timestamp <= ticks;
          have_rise <= 1'b1;
          have_fall <= 1'b0;
        end else if (fall && have_rise) begin
          fall_timestamp <= ticks;
          have_fall <= 1'b1;
        end
      end
      if (dividing) begin
        divide_remainder <= next_remainder;
        divide_quotient <= next_quotient;
        if (divide_count == 6'd31) begin
          frequency_hz <= next_quotient;
          dividing <= 1'b0;
        end else divide_count <= divide_count + 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
