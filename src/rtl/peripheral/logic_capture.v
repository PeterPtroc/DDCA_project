`default_nettype none
module logic_capture(input wire clk,input wire rst,input wire [7:0] capture_in,input wire we,input wire [4:0] off,input wire [31:0] wdata,input wire window_sel,input wire [11:0] window_index,output reg [31:0] rdata,output reg [7:0] sample_sync,output reg armed,output reg triggered,output reg done,output reg [12:0] count,output reg [11:0] trigger_index);
    reg [7:0] sync1,prev; reg [2:0] trig_ch; reg trig_edge; reg [11:0] depth,write_idx; reg [7:0] mem[0:4095]; wire edge_hit=trig_edge ? (prev[trig_ch]&&!sample_sync[trig_ch]) : (!prev[trig_ch]&&sample_sync[trig_ch]); integer i;
    always @* begin if(window_sel) rdata={24'd0,mem[window_index]}; else case(off) 5'h04:rdata={29'd0,done,triggered,armed};5'h08:rdata={29'd0,trig_ch};5'h0c:rdata={31'd0,trig_edge};5'h10:rdata={20'd0,depth};5'h14:rdata={19'd0,count};5'h18:rdata={20'd0,trigger_index};default:rdata=0;endcase end
    always @(posedge clk) begin
        if(rst) begin sync1<=0;sample_sync<=0;prev<=0;armed<=0;triggered<=0;done<=0;count<=0;write_idx<=0;depth<=4096;trig_ch<=0;trig_edge<=0;trigger_index<=0; end
        else begin sync1<=capture_in;sample_sync<=sync1;prev<=sample_sync;
            if(we) case(off) 0:begin if(wdata[1])begin armed<=0;triggered<=0;done<=0;count<=0;write_idx<=0;end if(wdata[0])begin armed<=1;triggered<=0;done<=0;count<=0;write_idx<=0;end end 8:trig_ch<=wdata[2:0];12:trig_edge<=wdata[0];16:depth<=(wdata<1)?1:(wdata>4096?4096:wdata[11:0]);default:;endcase
            if(armed&&!done) begin if(!triggered&&edge_hit) begin triggered<=1;mem[0]<=sample_sync;count<=1;write_idx<=1;trigger_index<=0;end else if(triggered) begin mem[write_idx]<=sample_sync;count<=count+1; if(write_idx==depth-1)begin done<=1;armed<=0;end else write_idx<=write_idx+1;end end
        end
    end
endmodule
`default_nettype wire
