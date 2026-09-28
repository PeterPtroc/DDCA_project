`default_nettype none
module perf_counter(input wire clk,input wire rst,input wire retire,input wire stall,input wire [1:0] fwd_ex,input wire [1:0] fwd_wb,input wire flush,branch,branch_taken,crc,input wire clear,input wire [4:0] off,output reg [31:0] rdata);
 reg [31:0] cycle,instret,stall_c,fwd_ex_c,fwd_wb_c,flush_c,branch_c,taken_c,crc_c;
 always @* case(off)0:rdata=cycle;1:rdata=instret;2:rdata=stall_c;3:rdata=fwd_ex_c;4:rdata=fwd_wb_c;5:rdata=flush_c;6:rdata=branch_c;7:rdata=taken_c;8:rdata=crc_c;default:rdata=0;endcase
 always @(posedge clk) begin if(rst||clear) begin cycle<=0;instret<=0;stall_c<=0;fwd_ex_c<=0;fwd_wb_c<=0;flush_c<=0;branch_c<=0;taken_c<=0;crc_c<=0;end else begin cycle<=cycle+1; if(retire)instret<=instret+1; if(stall)stall_c<=stall_c+1;fwd_ex_c<=fwd_ex_c+fwd_ex;fwd_wb_c<=fwd_wb_c+fwd_wb;if(flush)flush_c<=flush_c+1;if(branch)branch_c<=branch_c+1;if(branch_taken)taken_c<=taken_c+1;if(crc)crc_c<=crc_c+1;end end
endmodule
`default_nettype wire
