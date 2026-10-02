`default_nettype none

// Eight continuously running, compile-time fixed PWM test signals for Pmod JA.
// Counter widths are sized only for their respective period constants.
module fixed_test_signals (
    input  wire       clk,
    input  wire       rst,
    output wire [7:0] test_out
);
  reg [16:0] count_1khz;
  reg [15:0] count_2khz;
  reg [14:0] count_5khz;
  reg [12:0] count_14242hz;
  reg [12:0] count_20khz;
  reg [10:0] count_50khz;
  reg [9:0] count_100khz;
  reg [8:0] count_200khz;

  assign test_out[0] = count_1khz   < 17'd20000;
  assign test_out[1] = count_2khz   < 16'd15000;
  assign test_out[2] = count_5khz   < 15'd8000;
  assign test_out[3] = count_14242hz < 13'd3511;
  assign test_out[4] = count_20khz  < 13'd3000;
  assign test_out[5] = count_50khz  < 11'd1400;
  assign test_out[6] = count_100khz < 10'd800;
  assign test_out[7] = count_200khz < 9'd450;

  always @(posedge clk) begin
    if (rst) begin
      count_1khz   <= 17'd0;
      count_2khz   <= 16'd0;
      count_5khz   <= 15'd0;
      count_14242hz <= 13'd0;
      count_20khz  <= 13'd0;
      count_50khz  <= 11'd0;
      count_100khz <= 10'd0;
      count_200khz <= 9'd0;
    end else begin
      count_1khz   <= (count_1khz   == 17'd99999) ? 17'd0 : count_1khz + 1'b1;
      count_2khz   <= (count_2khz   == 16'd49999) ? 16'd0 : count_2khz + 1'b1;
      count_5khz   <= (count_5khz   == 15'd19999) ? 15'd0 : count_5khz + 1'b1;
      count_14242hz <= (count_14242hz == 13'd7020) ? 13'd0 : count_14242hz + 1'b1;
      count_20khz  <= (count_20khz  == 13'd4999)  ? 13'd0 : count_20khz + 1'b1;
      count_50khz  <= (count_50khz  == 11'd1999)  ? 11'd0 : count_50khz + 1'b1;
      count_100khz <= (count_100khz == 10'd999)   ? 10'd0 : count_100khz + 1'b1;
      count_200khz <= (count_200khz == 9'd499)    ? 9'd0 : count_200khz + 1'b1;
    end
  end
endmodule

`default_nettype wire
