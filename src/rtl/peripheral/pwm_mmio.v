`default_nettype none
module pwm_mmio(input wire clk,input wire rst,input wire we,input wire [3:0] off,input wire [31:0] wdata,output reg pwm_out,output reg [31:0] rdata);
    reg enable; reg [31:0] period,high,count; wire [31:0] high_clamped=(high>period)?period:high;
    always @* begin case(off) 0:rdata={31'd0,enable};4:rdata=period;8:rdata=high;default:rdata=0;endcase end
    always @(posedge clk) begin if(rst) begin enable<=0;period<=1000;high<=300;count<=0;pwm_out<=0;end else begin if(we) case(off) 0:enable<=wdata[0];4:period<=wdata;8:high<=wdata;default:;endcase if(!enable||period<2) begin count<=0;pwm_out<=0;end else begin if(count>=period-1)count<=0;else count<=count+1; pwm_out<=count<high_clamped;end end end
endmodule
`default_nettype wire
