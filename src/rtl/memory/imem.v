`default_nettype none
module imem #(
    parameter HEX_FILE = "build/hex/mvp.hex"
) (
    input wire [31:0] addr,
    output wire [31:0] rdata
);
    reg [31:0] mem [0:2047];
    integer i;
    initial begin
        for (i=0; i<2048; i=i+1) mem[i] = 32'h00000013;
        $readmemh(HEX_FILE, mem);
    end
    assign rdata = mem[addr[12:2]];
endmodule
`default_nettype wire
