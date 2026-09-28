`default_nettype none
module nexys_a7_top(input wire clk100,input wire reset,input wire [15:0] sw,input wire [4:0] btn,output wire [15:0] led,output wire uart_tx,output wire [7:0] pmod_ja, input wire [7:0] pmod_jb);
 wire pwm_out; wire [31:0] test_result; wire capture_done;
 soc_top soc(clk100,reset,sw,btn,pmod_jb,led,uart_tx,pwm_out,test_result,capture_done);
 assign pmod_ja={7'd0,pwm_out};
endmodule
`default_nettype wire
