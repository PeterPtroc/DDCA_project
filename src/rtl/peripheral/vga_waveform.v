`default_nettype none
module vga_waveform (
    input wire clk,
    input wire rst,
    input wire [7:0] sample,
    output wire [11:0] sample_index,
    output reg [3:0] vga_r,
    output reg [3:0] vga_g,
    output reg [3:0] vga_b,
    output reg vga_hs,
    output reg vga_vs
);
  reg [1:0] pixel_div;
  reg [9:0] hcount;
  reg [9:0] vcount;
  wire pixel_tick = pixel_div == 2'd3;
  wire visible = hcount < 640 && vcount < 480;
  wire wave_area = hcount >= 64 && hcount < 576 && vcount >= 32 && vcount < 448;
  wire [2:0] channel = (vcount - 32) / 52;
  wire [5:0] row = (vcount - 32) % 52;
  wire trace = sample[channel] ? (row >= 8 && row <= 10) : (row >= 40 && row <= 42);
  wire grid = (hcount[5:0] == 0) || (row == 51);
  assign sample_index = wave_area ? {(hcount - 64), 3'b000} : 12'd0;

  always @(posedge clk) begin
    if (rst) begin
      pixel_div <= 2'd0;
      hcount <= 10'd0;
      vcount <= 10'd0;
    end else begin
      pixel_div <= pixel_div + 1'b1;
      if (pixel_tick) begin
        if (hcount == 799) begin
          hcount <= 10'd0;
          if (vcount == 524) vcount <= 10'd0;
          else vcount <= vcount + 1'b1;
        end else hcount <= hcount + 1'b1;
      end
    end
  end

  always @* begin
    vga_hs = ~((hcount >= 656) && (hcount < 752));
    vga_vs = ~((vcount >= 490) && (vcount < 492));
    vga_r = 4'd0;
    vga_g = 4'd0;
    vga_b = 4'd0;
    if (visible && wave_area) begin
      if (trace) vga_g = 4'hf;
      else if (grid) begin
        vga_r = 4'h2;
        vga_g = 4'h2;
        vga_b = 4'h2;
      end
      if (hcount == 320) vga_r = 4'hf;
    end
  end
endmodule
`default_nettype wire
