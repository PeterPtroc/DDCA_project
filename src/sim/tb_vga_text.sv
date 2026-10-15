`timescale 1ns/1ps
module tb_vga_text;
  reg clk=0,pclk=0,rst=1,prst=1,cv=0,cw=0,rv=0,rw=0;
  reg [11:0] ca=0;
  reg [31:0] cd=0,ra=0,rd=0;
  reg [3:0] cs=15,rs=15;
  wire [31:0] cr,rr;
  wire ready,hs,vs;
  wire [3:0] red,green,blue;
  reg [7:0] reference_font[0:1023];
  reg [15:0] reference_cells[0:2399];
  integer checked=0;
  vga_text #(.BLINK_FRAME_BIT(0)) dut(.clk(clk),.rst(rst),.pixel_clk(pclk),.pixel_rst(prst),
      .cell_valid(cv),.cell_we(cw),.cell_addr(ca),.cell_wdata(cd),.cell_wstrb(cs),.cell_rdata(cr),
      .reg_valid(rv),.reg_we(rw),.reg_addr(ra),.reg_wdata(rd),.reg_wstrb(rs),.reg_ready(ready),.reg_rdata(rr),
      .red(red),.green(green),.blue(blue),.hsync(hs),.vsync(vs));
  always #5 clk=~clk;
  always #19.84127 pclk=~pclk;
  task cell_access(input bit write,input integer index,input [31:0] data,input [3:0] mask=15);
    @(negedge clk);cv=1;cw=write;ca=index;cd=data;cs=mask;
    @(negedge clk);cv=0;
  endtask
  task register_access(input bit write,input integer offset,input [31:0] data,input [3:0] mask=15);
    @(negedge clk);rv=1;rw=write;ra=offset;rd=data;rs=mask;
    while(!ready) @(negedge clk);
    @(negedge clk);rv=0;
  endtask
  function [11:0] color(input integer index);
    case(index)
      0:color=12'h000;1:color=12'h00a;2:color=12'h0a0;3:color=12'h0aa;
      4:color=12'ha00;5:color=12'ha0a;6:color=12'ha50;7:color=12'haaa;
      8:color=12'h555;9:color=12'h55f;10:color=12'h5f5;11:color=12'h5ff;
      12:color=12'hf55;13:color=12'hf5f;14:color=12'hff5;15:color=12'hfff;
    endcase
  endfunction
  // 使用独立的光栅计数器：复位后，寄存器输出滞后三个时钟沿。
  task check_frames(input integer frame_total,input bit enabled,input bit show_cursor);
    integer x,y,index,fg,bg;
    reg glyph;
    reg [15:0] cell_value;
    reg [11:0] expected;
    reg [9:0] hx[0:2],hy[0:2];
    bit frame;
    for(integer i=0;i<3;i++) begin hx[i]=0;hy[i]=0;end
    x=0;y=0;frame=0;
    for(integer cycle=0;cycle<frame_total*420000+2;cycle++) begin
      @(posedge pclk);#1;
      if(cycle>=2) begin
        if(hs!==!(hx[1]>=656 && hx[1]<752) || vs!==!(hy[1]>=490 && hy[1]<492))
          $fatal(1,"VGA sync mismatch x=%0d y=%0d",hx[1],hy[1]);
        expected=0;
        if(enabled && hx[1]<640 && hy[1]<480) begin
          index=(hy[1]/16)*80+hx[1]/8;cell_value=reference_cells[index];
          glyph=reference_font[(cell_value[6:0]*8)+(hy[1]%16)/2][hx[1]%8];
          // 本测试中闪烁状态逐帧翻转；实际实现使用帧计数器的第 5 位。
          if(show_cursor && index==2399 && hy[1]%16>=14 && ((checked/420000)%2==0)) glyph=1;
          fg=(cell_value>>8)&15;bg=(cell_value>>12)&15;
          expected=color(glyph ? fg : bg);
        end
        if({red,green,blue}!==expected)
          $fatal(1,"VGA pixel mismatch x=%0d y=%0d expected=%03x actual=%03x",hx[1],hy[1],expected,{red,green,blue});
        checked++;
      end
      hx[2]=hx[1];hy[2]=hy[1];hx[1]=hx[0];hy[1]=hy[0];hx[0]=x;hy[0]=y;
      if(x==799) begin x=0;if(y==524) begin y=0;frame=!frame;end else y++;end else x++;
    end
  endtask
  initial begin
    $readmemh("build/ptrocos_text/font-reference.hex",reference_font);
    repeat(8) @(negedge clk);rst=0;prst=0;
    for(integer i=0;i<2400;i++) begin
      reference_cells[i]={4'(i%16),4'((i/16)%16),8'(32+i%95)};
      cell_access(1,i,reference_cells[i]);
    end
    cell_access(1,2399,32'h00001e00,4'b0010);
    reference_cells[2399][15:8]=8'h1e;
    cell_access(1,2399,32'h00000020,4'b0001);
    reference_cells[2399][7:0]=8'h20;
    cell_access(1,2399,32'hdead0000,4'b1100);
    cell_access(0,2399,0);if(cr!==32'h1e20) $fatal(1,"Cell strobes/read");
    cell_access(1,2400,32'habcd);cell_access(0,2400,0);if(cr!==0) $fatal(1,"VRAM bound");
    @(negedge pclk);rst=0;prst=0;
    register_access(1,0,7);register_access(1,4,2399);
    register_access(0,0,0);if(rr!==7) $fatal(1,"Control read");
    register_access(1,0,0,4'b0010);register_access(0,0,0);if(rr!==7) $fatal(1,"Control strobe");
    register_access(0,4,0);if(rr!==2399) $fatal(1,"Cursor read");
    register_access(0,12,0);if(rr!==32'h001e0050) $fatal(1,"Geometry read");
    // 从新一帧的边界开始独立检查，并计入流水线延迟。
    wait(dut.x==799 && dut.y==524);@(posedge pclk);@(negedge pclk);
    // 首个检查帧为奇数帧（隐藏光标），第二帧为偶数帧（显示光标）。
    checked=420000;
    check_frames(2,1,1);
    register_access(0,8,0);if(rr<3) $fatal(1,"Frame counter");
    register_access(1,0,0);
    wait(dut.x==799 && dut.y==524);@(posedge pclk);@(negedge pclk);
    check_frames(1,0,0);
    // 在寄存器事务进行期间复位；同时复位两个时钟域。
    @(negedge clk);rv=1;rw=1;ra=0;rd=7;
    repeat(2) @(negedge clk);rst=1;prst=1;rv=0;
    repeat(8) @(negedge pclk);rst=0;prst=0;
    register_access(0,0,0);if(rr!==1) $fatal(1,"Joint reset did not restore display control");
    register_access(0,4,0);if(rr!==4095) $fatal(1,"Joint reset cursor");
    $display("VGA TEXT PASS pixels=%0d full-raster colors font cursor blink byte-enables bounds CDC reset",checked-420000);
    $finish;
  end
  initial begin #150000000;$fatal(1,"VGA test timeout");end
endmodule
