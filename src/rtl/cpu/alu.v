`default_nettype none
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [4:0]  op,
    output reg  [31:0] y
);
    localparam ALU_ADD=5'd0, ALU_SUB=5'd1, ALU_SLL=5'd2, ALU_SLT=5'd3,
               ALU_SLTU=5'd4, ALU_XOR=5'd5, ALU_SRL=5'd6, ALU_SRA=5'd7,
               ALU_OR=5'd8, ALU_AND=5'd9, ALU_PASS_B=5'd10;
    always @* begin
        case (op)
            ALU_ADD:    y = a + b;
            ALU_SUB:    y = a - b;
            ALU_SLL:    y = a << b[4:0];
            ALU_SLT:    y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU:   y = (a < b) ? 32'd1 : 32'd0;
            ALU_XOR:    y = a ^ b;
            ALU_SRL:    y = a >> b[4:0];
            ALU_SRA:    y = $signed(a) >>> b[4:0];
            ALU_OR:     y = a | b;
            ALU_AND:    y = a & b;
            ALU_PASS_B: y = b;
            default:    y = 32'd0;
        endcase
    end
endmodule
`default_nettype wire
