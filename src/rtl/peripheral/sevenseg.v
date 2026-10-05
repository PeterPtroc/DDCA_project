`default_nettype none
module sevenseg (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [3:0] off,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output reg [7:0] an,
    output reg [6:0] seg,
    output reg dp
);
  reg [31:0] display_data0;
  reg [31:0] display_data1;
  reg [7:0] display_dp;
  reg [31:0] display_ctrl;
  reg [16:0] refresh_count;
  wire [2:0] digit = refresh_count[16:14];
  reg [7:0] code;
  reg [6:0] glyph;

  always @* begin
    case (off)
      4'h0: rdata = display_data0;
      4'h4: rdata = display_data1;
      4'h8: rdata = {24'd0, display_dp};
      4'hc: rdata = display_ctrl;
      default: rdata = 32'd0;
    endcase
  end

  always @* begin
    case (digit)
      3'd0: code = display_data0[7:0];
      3'd1: code = display_data0[15:8];
      3'd2: code = display_data0[23:16];
      3'd3: code = display_data0[31:24];
      3'd4: code = display_data1[7:0];
      3'd5: code = display_data1[15:8];
      3'd6: code = display_data1[23:16];
      default: code = display_data1[31:24];
    endcase
    // Active-low segments. Codes 0..9 are decimal, 0x10 is '-', and
    // all other values are blank. One byte encodes each display position.
    case (code)
      8'h00: glyph = 7'b1000000;
      8'h01: glyph = 7'b1111001;
      8'h02: glyph = 7'b0100100;
      8'h03: glyph = 7'b0110000;
      8'h04: glyph = 7'b0011001;
      8'h05: glyph = 7'b0010010;
      8'h06: glyph = 7'b0000010;
      8'h07: glyph = 7'b1111000;
      8'h08: glyph = 7'b0000000;
      8'h09: glyph = 7'b0010000;
      8'h10: glyph = 7'b0111111;
      default: glyph = 7'b1111111;
    endcase
    an  = display_ctrl[0] ? ~(8'b1 << digit) : 8'hff;
    seg = glyph;
    dp  = display_ctrl[0] ? ~display_dp[digit] : 1'b1;
  end

  always @(posedge clk) begin
    if (rst) begin
      display_data0 <= 32'h1f1f1f1f;
      display_data1 <= 32'h1f1f1f1f;
      display_dp <= 8'd0;
      display_ctrl <= 32'd0;
      refresh_count <= 17'd0;
    end else begin
      refresh_count <= refresh_count + 1'b1;
      if (we)
        case (off)
          4'h0: display_data0 <= wdata;
          4'h4: display_data1 <= wdata;
          4'h8: display_dp <= wdata[7:0];
          4'hc: display_ctrl <= wdata;
          default: ;
        endcase
    end
  end
endmodule
`default_nettype wire
