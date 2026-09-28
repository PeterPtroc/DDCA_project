`default_nettype none
module uart_tx #(parameter DIVIDER=868)(input wire clk,input wire rst,input wire start,input wire [7:0] data,output wire ready,output reg tx);
    reg busy; reg [15:0] divcnt; reg [3:0] bitcnt; reg [9:0] shreg;
    assign ready=!busy;
    always @(posedge clk) begin
        if(rst) begin busy<=0;divcnt<=0;bitcnt<=0;shreg<=10'h3ff;tx<=1;end
        else if(!busy) begin tx<=1; if(start) begin busy<=1;divcnt<=0;bitcnt<=0;shreg<={1'b1,data,1'b0}; end end
        else if(divcnt==DIVIDER-1) begin divcnt<=0;tx<=shreg[0];shreg<={1'b1,shreg[9:1]};if(bitcnt==9)busy<=0;else bitcnt<=bitcnt+1;end else divcnt<=divcnt+1;
    end
endmodule
`default_nettype wire
