`default_nettype none
module dmem (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output wire [31:0] rdata
);
    reg [31:0] mem [0:1023];
    integer i;
    assign rdata = (addr[31:12] == 20'h10000) ? mem[addr[11:2]] : 32'd0;
    always @(posedge clk) begin
        if (rst) begin
            for (i=0; i<1024; i=i+1) mem[i] <= 32'd0;
        end else if (we && addr[31:12] == 20'h10000) begin
            mem[addr[11:2]] <= wdata;
        end
    end
endmodule
`default_nettype wire
