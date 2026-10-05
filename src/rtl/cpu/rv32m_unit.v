`default_nettype none
// One request at a time. Inputs are sampled only on start && !busy.
// All normal operations take 32 iterations; divide-by-zero completes early.
// Reset also cancels a speculative operation when an older instruction traps.
module rv32m_unit (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [2:0] op,
    input wire [31:0] a,
    input wire [31:0] b,
    output reg busy,
    output reg done,
    output reg [31:0] result
);
  reg [2:0] operation;
  reg [5:0] count;
  reg negative_product, negative_quotient, negative_remainder;
  reg [63:0] product, multiplicand;
  reg [31:0] multiplier, quotient, divisor;
  reg [32:0] remainder;

  wire signed_a = (op == 3'd1 || op == 3'd2 || op == 3'd4 || op == 3'd6);
  wire signed_b = (op == 3'd1 || op == 3'd4 || op == 3'd6);
  wire sign_a = signed_a && a[31];
  wire sign_b = signed_b && b[31];
  wire [31:0] magnitude_a = sign_a ? (~a + 32'd1) : a;
  wire [31:0] magnitude_b = sign_b ? (~b + 32'd1) : b;
  wire [63:0] product_next = product + (multiplier[0] ? multiplicand : 64'd0);
  wire [63:0] signed_product = negative_product ? (~product_next + 64'd1) : product_next;
  wire [32:0] remainder_shift = {remainder[31:0], quotient[31]};
  wire subtract_divisor = remainder_shift >= {1'b0, divisor};
  wire [32:0] remainder_next = subtract_divisor ?
      remainder_shift - {1'b0, divisor} : remainder_shift;
  wire [31:0] quotient_next = {quotient[30:0], subtract_divisor};
  wire [31:0] signed_quotient = negative_quotient ? (~quotient_next + 32'd1) : quotient_next;
  wire [31:0] signed_remainder = negative_remainder ? (~remainder_next[31:0] + 32'd1) : remainder_next[31:0];

  always @(posedge clk) begin
    if (rst) begin
      busy <= 1'b0;
      done <= 1'b0;
      result <= 32'd0;
      operation <= 0;
      count <= 0;
      negative_product <= 0;
      negative_quotient <= 0;
      negative_remainder <= 0;
      product <= 0;
      multiplicand <= 0;
      multiplier <= 0;
      quotient <= 0;
      divisor <= 0;
      remainder <= 0;
    end else begin
      done <= 1'b0;
      if (start && !busy) begin
        operation <= op;
        count <= 0;
        negative_product <= sign_a ^ sign_b;
        negative_quotient <= sign_a ^ sign_b;
        negative_remainder <= sign_a;
        product <= 0;
        multiplicand <= {32'd0, magnitude_a};
        multiplier <= magnitude_b;
        quotient <= magnitude_a;
        divisor <= magnitude_b;
        remainder <= 0;
        if (op[2] && b == 0) begin
          result <= op[1] ? a : 32'hffffffff;
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          busy <= 1'b1;
        end
      end else if (busy) begin
        count <= count + 1'b1;
        if (!operation[2]) begin
          product <= product_next;
          multiplicand <= multiplicand << 1;
          multiplier <= multiplier >> 1;
          if (count == 31) result <= operation == 0 ? signed_product[31:0] : signed_product[63:32];
        end else begin
          remainder <= remainder_next;
          quotient <= quotient_next;
          if (count == 31) result <= operation[1] ? signed_remainder : signed_quotient;
        end
        if (count == 31) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
      end
    end
  end
endmodule
`default_nettype wire
