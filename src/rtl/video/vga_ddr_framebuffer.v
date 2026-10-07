`default_nettype none
// RGB565 or 4x monochrome scanout, with a bounded asynchronous line FIFO.
// A slot is written only while its pixel->UI mailbox is outstanding, and becomes
// readable only after completion. Pixel ownership lasts through the line's end.
module vga_ddr_framebuffer #(
    parameter WIDTH=640,HEIGHT=480,H_TOTAL=800,V_TOTAL=525
) (
    input wire clk,rst,ui_clk,ui_rst,pixel_clk,pixel_rst,
    input wire reg_valid,reg_we,
    input wire [31:0] reg_addr,reg_wdata,
    input wire [3:0] reg_wstrb,
    output wire reg_ready,
    output wire [31:0] reg_rdata,
    output wire [26:0] axi_araddr,
    output wire [7:0] axi_arlen,
    output wire [2:0] axi_arsize,
    output wire [1:0] axi_arburst,
    output wire axi_arvalid,
    input wire axi_arready,
    input wire [127:0] axi_rdata,
    input wire [1:0] axi_rresp,
    input wire axi_rlast,axi_rvalid,
    output wire axi_rready,
    output reg [3:0] red,green,blue,
    output reg graphics_selected,
    output wire [9:0] scan_x,scan_y
);
  localparam ROW_BEATS=WIDTH/8;
  localparam MONO_BEATS=((WIDTH+3)/4+127)/128;
  localparam MONO_HEIGHT=(HEIGHT+3)/4;
  localparam IDLE=0,CALC=1,PREPARE=2,ADDRESS=3,DATA=4,COMPLETE=5;
  (* ram_style="block" *) reg [127:0] lines[0:511];
  wire cv,cw;wire [31:0] ca,cd;wire [3:0] cs;reg [31:0] cr;
  word_bus_cdc register_cdc (
      .source_clk(clk),.source_rst(rst),.source_valid(reg_valid),.source_we(reg_we),
      .source_addr(reg_addr),.source_wdata(reg_wdata),.source_wstrb(reg_wstrb),
      .source_ready(reg_ready),.source_rdata(reg_rdata),.source_error(),
      .target_clk(ui_clk),.target_rst(ui_rst),.target_valid(cv),.target_we(cw),
      .target_addr(ca),.target_wdata(cd),.target_wstrb(cs),.target_ready(cv),
      .target_rdata(cr),.target_error(1'b0)
  );
  reg [9:0] x,y;
  assign scan_x=x;assign scan_y=y;
  wire blank=y>=HEIGHT;
  reg swap_window_pixel;
  (* ASYNC_REG="TRUE" *) reg [1:0] blank_sync;
  reg frame_valid;
  wire frame_ready,fv,fw,fr;
  reg [31:0] wanted_epoch,frame_epoch_hold,underflows,frame_under_hold;
  wire [31:0] fa,fd,frame_response,frame_return;
  wire [3:0] fs;
  word_bus_cdc frame_cdc (
      .source_clk(pixel_clk),.source_rst(pixel_rst),.source_valid(frame_valid),.source_we(1'b1),
      .source_addr(frame_epoch_hold),.source_wdata(frame_under_hold),.source_wstrb(4'hf),
      .source_ready(frame_ready),.source_rdata(frame_return),.source_error(),
      .target_clk(ui_clk),.target_rst(ui_rst),.target_valid(fv),.target_we(fw),
      .target_addr(fa),.target_wdata(fd),.target_wstrb(fs),.target_ready(fr),
      .target_rdata(frame_response),.target_error(1'b0)
  );
  reg [3:0] request,bank_ready,bank_failed;
  wire [3:0] request_ready,row_valid,row_complete,row_error,return_error;
  reg [31:0] request_epoch[0:3],bank_epoch[0:3];
  reg [8:0] request_row[0:3],bank_row[0:3];
  reg [9:0] wanted_row[0:3];
  wire [31:0] row_epoch[0:3],row_number[0:3];
  genvar b;
  generate for(b=0;b<4;b=b+1) begin:row_cdc
    word_bus_cdc mailbox (
        .source_clk(pixel_clk),.source_rst(pixel_rst),.source_valid(request[b]),.source_we(1'b1),
        .source_addr(request_epoch[b]),.source_wdata({23'd0,request_row[b]}),.source_wstrb(4'hf),
        .source_ready(request_ready[b]),.source_rdata(),.source_error(return_error[b]),
        .target_clk(ui_clk),.target_rst(ui_rst),.target_valid(row_valid[b]),.target_we(),
        .target_addr(row_epoch[b]),.target_wdata(row_number[b]),.target_wstrb(),.target_ready(row_complete[b]),
        .target_rdata(32'd0),.target_error(row_error[b])
    );
  end endgenerate
  reg [2:0] state;
  reg [1:0] slot,round_robin;
  reg [31:0] next_base,next_stride,pending_base,pending_stride,active_base,active_stride,active_epoch;
  reg [31:0] next_format;
  reg pending_mono,active_mono;
  reg pending,pending_enable,active_enable,config_fault,dma_fault,underrun_sticky;
  reg [31:0] swaps,frames,underflow_snapshot,read_beats,read_errors;
  reg [31:0] row_address;
  // Latch the mailbox result before entering the row-address multiplier. This
  // keeps the CDC valid pulse out of the long UI-clock address path.
  reg [31:0] row_base_latched,row_stride_latched,row_index_latched;
  reg [7:0] remaining,burst_count,received;
  reg [6:0] beat_base;
  reg row_bad;
  wire next_mono=next_format==1;
  // Keep each height constant before multiplication. Selecting the height at
  // the multiplier input creates a general DSP multiply on the commit enable.
  wire [63:0] next_rgb_end={32'd0,next_base}+({32'd0,next_stride}*(HEIGHT-1))+WIDTH*2;
  wire [63:0] next_mono_end={32'd0,next_base}+({32'd0,next_stride}*(MONO_HEIGHT-1))+MONO_BEATS*16;
  wire valid_config=next_base>=32'h80000000 && next_base[3:0]==0 && next_stride[3:0]==0 &&
      next_format<=1 && (next_mono ?
          (next_stride>=MONO_BEATS*16 && next_mono_end<=64'h88000000) :
          (next_stride>=WIDTH*2 && next_rgb_end<=64'h88000000));
  assign fr=state==IDLE && fv;
  assign frame_response={30'd0,(pending && blank_sync[1]) ? pending_mono : active_mono,
      (pending && blank_sync[1]) ? pending_enable : active_enable};
  assign axi_araddr=row_address[26:0];assign axi_arlen=burst_count-1'b1;
  assign axi_arsize=4;assign axi_arburst=1;
  assign axi_arvalid=state==ADDRESS;assign axi_rready=state==DATA;
  generate for(b=0;b<4;b=b+1) begin:row_reply
    assign row_complete[b]=state==COMPLETE && slot==b;
    assign row_error[b]=row_bad;
  end endgenerate
  function [31:0] merge(input [31:0] old_value,new_value,input [3:0] strobes);
    integer j;
    begin
      merge=old_value;
      for(j=0;j<4;j=j+1) if(strobes[j]) merge[j*8+:8]=new_value[j*8+:8];
    end
  endfunction
  always @* begin
    case(ca[7:2])
      0:cr=next_base;1:cr=next_stride;2:cr=0;
      3:cr={27'd0,underrun_sticky,dma_fault,config_fault,pending,active_enable};
      4:cr=active_base;5:cr=active_stride;6:cr=frames;7:cr=swaps;
      8:cr=underflow_snapshot;9:cr=read_beats;10:cr=read_errors;
      11:cr=(HEIGHT<<16)|WIDTH;12:cr=16'h0565;
      13:cr=next_format;14:cr={31'd0,active_mono};
      default:cr=0;
    endcase
  end
  integer choice,candidate,j;
  reg [8:0] boundary_beats;
  reg [7:0] planned_count;
  always @* begin
    choice=-1;
    for(j=0;j<4;j=j+1) begin
      candidate=(round_robin+j)&3;
      if(choice<0 && row_valid[candidate]) choice=candidate;
    end
    boundary_beats=9'd256-{1'b0,row_address[11:4]};
    planned_count=remaining<16 ? remaining : 16;
    if(boundary_beats<planned_count) planned_count=boundary_beats[7:0];
  end
  always @(posedge ui_clk) begin
    if(ui_rst) begin
      blank_sync<=0;state<=IDLE;slot<=0;round_robin<=0;
      next_base<=32'h81000000;next_stride<=WIDTH*2;
      next_format<=0;pending_mono<=0;active_mono<=0;
      pending_base<=0;pending_stride<=0;pending<=0;pending_enable<=0;
      active_base<=32'h81000000;active_stride<=WIDTH*2;active_epoch<=0;active_enable<=0;
      config_fault<=0;dma_fault<=0;underrun_sticky<=0;swaps<=0;frames<=0;
      underflow_snapshot<=0;read_beats<=0;read_errors<=0;
      row_address<=0;remaining<=0;burst_count<=1;received<=0;beat_base<=0;row_bad<=0;
      row_base_latched<=0;row_stride_latched<=0;row_index_latched<=0;
    end else begin
      // Close two whole lines early, leaving more than the CDC latency before
      // visible pixels even when an AXI transaction finishes near the deadline.
      blank_sync<={blank_sync[0],swap_window_pixel};
      if(cv && cw) case(ca[7:2])
        0:next_base<=merge(next_base,cd,cs);
        1:next_stride<=merge(next_stride,cd,cs);
        2:if(cs[0]) begin
          if(cd[2]) begin config_fault<=0;dma_fault<=0;underrun_sticky<=0;end
          if(cd[0]) begin
            if(pending || (cd[1] && !valid_config)) config_fault<=1;
            else begin
              pending<=1;pending_enable<=cd[1];pending_base<=next_base;pending_stride<=next_stride;
              pending_mono<=next_mono;
            end
          end
        end
        13:if(cs==4'hf) next_format<=cd;
        default:begin end
      endcase
      case(state)
        IDLE: if(fv) begin
          active_epoch<=fa;frames<=fa;
          if(fd!=underflow_snapshot) underrun_sticky<=1;
          underflow_snapshot<=fd;
          // A late event never changes the front buffer during visible pixels.
          if(pending && blank_sync[1]) begin
            active_base<=pending_base;active_stride<=pending_stride;active_enable<=pending_enable;
            active_mono<=pending_mono;
            pending<=0;swaps<=swaps+1'b1;
          end
        end else if(choice>=0) begin
          slot<=choice[1:0];round_robin<=choice[1:0]+1'b1;
          beat_base<=0;remaining<=active_mono ? MONO_BEATS : ROW_BEATS;row_bad<=0;
          if(!active_enable || row_epoch[choice]!=active_epoch || row_number[choice]>=HEIGHT) begin
            row_bad<=1;state<=COMPLETE;
          end else begin
            row_base_latched<=active_base;
            row_stride_latched<=active_stride;
            row_index_latched<=active_mono ? (row_number[choice]>>2) : row_number[choice];
            state<=CALC;
          end
        end
        CALC:begin
          row_address<=row_base_latched+row_index_latched*row_stride_latched;
          state<=PREPARE;
        end
        PREPARE:begin
          burst_count<=planned_count;received<=0;state<=ADDRESS;
        end
        ADDRESS:if(axi_arready) state<=DATA;
        DATA:if(axi_rvalid) begin
          read_beats<=read_beats+1'b1;
          if(!row_bad && axi_rresp==0 && received<burst_count)
            lines[{slot,(beat_base+received[6:0])}]<=axi_rdata;
          if(received!=255) received<=received+1'b1;
          if(axi_rresp!=0 || received>=burst_count) row_bad<=1;
          if(axi_rlast) begin
            if(row_bad || axi_rresp!=0 || received+1'b1!=burst_count) begin
              row_bad<=1;dma_fault<=1;read_errors<=read_errors+1'b1;state<=COMPLETE;
            end else if(remaining==burst_count) state<=COMPLETE;
            else begin
              remaining<=remaining-burst_count;beat_base<=beat_base+burst_count;
              row_address<=row_address+{20'd0,burst_count,4'd0};state<=PREPARE;
            end
          end
        end
        COMPLETE:state<=IDLE;
        default:state<=IDLE;
      endcase
    end
  end
  reg [31:0] queue_epoch,display_epoch;
  reg fetch_enable,mode_on,line_good,fetch_mono,display_mono;
  wire [1:0] scan_slot=y[1:0];
  wire line_ready=bank_ready[scan_slot] && !bank_failed[scan_slot] &&
      bank_epoch[scan_slot]==display_epoch && bank_row[scan_slot]==y;
  integer k;
  reg [9:0] following_row;
  always @(posedge pixel_clk) begin
    if(pixel_rst) begin
      x<=0;y<=0;wanted_epoch<=0;frame_epoch_hold<=0;frame_under_hold<=0;frame_valid<=0;
      underflows<=0;queue_epoch<=0;display_epoch<=0;fetch_enable<=0;mode_on<=0;line_good<=0;
      fetch_mono<=0;display_mono<=0;
      swap_window_pixel<=0;
      request<=0;bank_ready<=0;bank_failed<=0;
      for(k=0;k<4;k=k+1) begin
        request_epoch[k]<=0;request_row[k]<=0;bank_epoch[k]<=0;bank_row[k]<=0;wanted_row[k]<=k;
      end
    end else begin
      swap_window_pixel<=blank && y<V_TOTAL-2;
      if(x==H_TOTAL-1) begin
        x<=0;
        if(y==V_TOTAL-1) begin
          y<=0;display_epoch<=wanted_epoch;
          if(queue_epoch==wanted_epoch) begin mode_on<=fetch_enable;display_mono<=fetch_mono;end
        end else y<=y+1'b1;
        if(y<HEIGHT) begin bank_ready[scan_slot]<=0;wanted_row[scan_slot]<=y+4;end
      end else x<=x+1'b1;
      if(x==0 && y==HEIGHT) wanted_epoch<=wanted_epoch+1'b1;
      if(!frame_valid && blank && frame_epoch_hold!=wanted_epoch) begin
        frame_valid<=1;frame_epoch_hold<=wanted_epoch;frame_under_hold<=underflows;
      end
      if(frame_valid && frame_ready) begin
        frame_valid<=0;queue_epoch<=frame_epoch_hold;fetch_enable<=frame_return[0];
        fetch_mono<=frame_return[1];
        for(k=0;k<4;k=k+1) begin
          following_row={y[9:2],2'b00}+k;
          if(following_row<=y) following_row=following_row+4;
          wanted_row[k]<=blank ? k : following_row;
        end
      end
      if(x==0 && y<HEIGHT) begin
        line_good<=line_ready;
        if(mode_on && !line_ready) underflows<=underflows+1'b1;
      end
      for(k=0;k<4;k=k+1) begin
        if(request[k] && request_ready[k]) begin
          request[k]<=0;bank_ready[k]<=1;bank_failed[k]<=return_error[k];
          bank_epoch[k]<=request_epoch[k];bank_row[k]<=request_row[k];
        end else if(!request[k] && fetch_enable && queue_epoch==wanted_epoch && wanted_row[k]<HEIGHT &&
            !(y<HEIGHT && x!=0 && line_good && scan_slot==k) &&
            (!bank_ready[k] || bank_epoch[k]!=queue_epoch || bank_row[k]!=wanted_row[k])) begin
          request[k]<=1;bank_ready[k]<=0;bank_failed[k]<=0;
          request_epoch[k]<=queue_epoch;request_row[k]<=wanted_row[k][8:0];
        end
      end
    end
  end
  reg [127:0] scan_word;
  reg [2:0] lane;
  reg [6:0] mono_lane;
  reg mono1;
  reg [15:0] pixel;
  reg active1,active2,mode1,mode2;
  always @(posedge pixel_clk) begin
    scan_word<=lines[{scan_slot,(display_mono ? {6'd0,x[9]} : x[9:3])}];lane<=x[2:0];
    mono_lane<=x[8:2];mono1<=display_mono;
    pixel<=mono1 ? {16{scan_word[mono_lane]}} : scan_word>>{lane,4'b0000};
    active1<=x<WIDTH && y<HEIGHT && mode_on && (x==0 ? line_ready : line_good);
    active2<=active1;mode1<=mode_on;mode2<=mode1;graphics_selected<=mode2;
    if(active2) begin red<=pixel[15:12];green<=pixel[10:7];blue<=pixel[4:1];end
    else begin red<=0;green<=0;blue<=0;end
    if(pixel_rst) begin
      active1<=0;active2<=0;mode1<=0;mode2<=0;graphics_selected<=0;red<=0;green<=0;blue<=0;
    end
  end
endmodule
`default_nettype wire
