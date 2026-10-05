`default_nettype none
// 640x480 at 60 Hz with a 25.2 MHz pixel clock: 800x525 total, negative sync.
// 80x30 text, 8x16 cells. Public-domain 8x8 font rows are repeated vertically.
// VRAM: 2400 words, low 16 bits = {background[3:0],foreground[3:0],ASCII[7:0]}.
// A same-cell CPU write during scanout may show old/new data for that cell.
module vga_text #(parameter BLINK_FRAME_BIT=5) (
    input wire clk, rst, pixel_clk, pixel_rst,
    input wire cell_valid, cell_we,
    input wire [11:0] cell_addr,
    input wire [31:0] cell_wdata,
    input wire [3:0] cell_wstrb,
    output wire [31:0] cell_rdata,
    input wire reg_valid, reg_we,
    input wire [31:0] reg_addr, reg_wdata,
    input wire [3:0] reg_wstrb,
    output wire reg_ready,
    output wire [31:0] reg_rdata,
    output reg [3:0] red, green, blue,
    output reg hsync, vsync
);
  (* ram_style="block" *) reg [15:0] cells [0:4095];
  integer i;
  initial begin
    for(i=0;i<4096;i=i+1) cells[i]=16'h0720;
  end
  reg [15:0] cell_cpu;
  reg cell_read_valid;
  assign cell_rdata=cell_read_valid ? {16'd0,cell_cpu} : 32'd0;
  // Keep reset off BRAM control pins. Only the output-valid FF needs reset.
  always @(posedge clk) begin
    cell_cpu<=cells[cell_addr];
    if(rst) cell_read_valid<=0;
    else if(cell_valid && !cell_we) cell_read_valid<=cell_addr<2400;
    if(cell_valid && cell_addr<2400) begin
      if(cell_we) begin
        if(cell_wstrb[0]) cells[cell_addr][7:0]<=cell_wdata[7:0];
        if(cell_wstrb[1]) cells[cell_addr][15:8]<=cell_wdata[15:8];
      end
    end
  end
  wire pv,pw;
  wire [31:0] pa,pd;
  wire [3:0] ps;
  reg [31:0] pr;
  word_bus_cdc register_cdc (
      .source_clk(clk),.source_rst(rst),.source_valid(reg_valid),.source_we(reg_we),
      .source_addr(reg_addr),.source_wdata(reg_wdata),.source_wstrb(reg_wstrb),
      .source_ready(reg_ready),.source_rdata(reg_rdata),.source_error(),
      .target_clk(pixel_clk),.target_rst(pixel_rst),.target_valid(pv),.target_we(pw),
      .target_addr(pa),.target_wdata(pd),.target_wstrb(ps),.target_ready(pv),
      .target_rdata(pr),.target_error(1'b0)
  );
  reg [2:0] control;
  reg [11:0] cursor;
  reg [31:0] frames;
  reg [9:0] x,y;
  wire active=x<640 && y<480;
  wire raw_hsync=!(x>=656 && x<752);
  wire raw_vsync=!(y>=490 && y<492);
  // Constant multiply by 80, followed by the column index.
  wire [11:0] scan_cell=({7'd0,y[8:4]}<<6)+({7'd0,y[8:4]}<<4)+{5'd0,x[9:3]};
  always @* begin
    case(pa[7:2])
      0:pr={29'd0,control};
      1:pr={20'd0,cursor};
      2:pr=frames;
      3:pr=32'h001e0050;
      4:pr={12'd0,y,x};
      5:pr=25200000;
      default:pr=0;
    endcase
  end
  always @(posedge pixel_clk) begin
    if(pixel_rst) begin x<=0;y<=0;frames<=0;control<=1;cursor<=12'hfff;end
    else begin
      if(x==799) begin
        x<=0;
        if(y==524) begin y<=0;frames<=frames+1'b1;end
        else y<=y+1'b1;
      end else x<=x+1'b1;
      if(pv && pw) begin
        if(pa[7:2]==0 && ps[0]) control<=pd[2:0];
        if(pa[7:2]==1) begin
          if(ps[0]) cursor[7:0]<=pd[7:0];
          if(ps[1]) cursor[11:8]<=pd[11:8];
        end
      end
    end
  end
  reg [15:0] cell_pixel;
  reg [2:0] glyph_x1, glyph_x2;
  reg [3:0] glyph_y1;
  reg [7:0] attribute2;
  reg active1,active2,hs1,hs2,vs1,vs2,cursor1,cursor2;
  wire [7:0] font_row;
  text_font_rom font(.clk(pixel_clk),.addr({cell_pixel[6:0],glyph_y1[3:1]}),.row(font_row));
  wire foreground=font_row[glyph_x2] || cursor2;
  wire [3:0] color=foreground ? attribute2[3:0] : attribute2[7:4];
  // Standard 16-color text palette (RGB 0/5/10/15, brown exception at index 6).
  function [11:0] palette(input [3:0] index);
    begin
      palette={index[2] ? (index[3] ? 4'hf : 4'ha) : (index[3] ? 4'h5 : 4'h0),
               index[1] ? (index[3] ? 4'hf : 4'ha) : (index[3] ? 4'h5 : 4'h0),
               index[0] ? (index[3] ? 4'hf : 4'ha) : (index[3] ? 4'h5 : 4'h0)};
      if(index==6) palette=12'ha50;
    end
  endfunction
  always @(posedge pixel_clk) begin
    cell_pixel<=cells[active ? scan_cell : 12'd0];
    glyph_x1<=x[2:0];glyph_y1<=y[3:0];
    active1<=active && control[0];hs1<=raw_hsync;vs1<=raw_vsync;
    cursor1<=control[1] && scan_cell==cursor && y[3:0]>=14 &&
             (!control[2] || !frames[BLINK_FRAME_BIT]);
    glyph_x2<=glyph_x1;attribute2<=cell_pixel[15:8];
    active2<=active1;hs2<=hs1;vs2<=vs1;cursor2<=cursor1;
    hsync<=hs2;vsync<=vs2;
    if(active2) {red,green,blue}<=palette(color);
    else {red,green,blue}<=0;
    if(pixel_rst) begin
      active1<=0;active2<=0;hs1<=1;hs2<=1;vs1<=1;vs2<=1;
      cursor1<=0;cursor2<=0;red<=0;green<=0;blue<=0;hsync<=1;vsync<=1;
    end
  end
endmodule
`default_nettype wire
