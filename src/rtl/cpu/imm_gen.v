`default_nettype none
module imm_gen (
    input  wire [31:0] insn,
    input  wire [ 2:0] imm_type,
    output reg  [31:0] imm
);
  localparam IMM_I = 3'd0, IMM_S = 3'd1, IMM_B = 3'd2, IMM_U = 3'd3, IMM_J = 3'd4;
  always @* begin
    case (imm_type)
      IMM_I:   imm = {{20{insn[31]}}, insn[31:20]};
      IMM_S:   imm = {{20{insn[31]}}, insn[31:25], insn[11:7]};
      IMM_B:   imm = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
      IMM_U:   imm = {insn[31:12], 12'b0};
      IMM_J:   imm = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
      default: imm = 32'd0;
    endcase
  end
endmodule
`default_nettype wire
