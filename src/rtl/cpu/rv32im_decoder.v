`default_nettype none
// Extend the shared RV32I decoder with RV32M instructions.
module rv32im_decoder (
    input wire [31:0] insn,
    output wire valid, uses_rs1, uses_rs2, reg_we,
    output wire mem_we, mem_re, branch, jump, jalr, alu_src_imm, wb_mem, is_crc,
    output wire [4:0] alu_op,
    output wire [2:0] imm_type
);
  wire base_valid, base_rs1, base_rs2, base_we;
  wire is_m = insn[6:0] == 7'b0110011 && insn[31:25] == 7'b0000001;
  decoder base (
      .insn(insn), .valid(base_valid), .uses_rs1(base_rs1), .uses_rs2(base_rs2),
      .reg_we(base_we), .mem_we(mem_we), .mem_re(mem_re), .branch(branch),
      .jump(jump), .jalr(jalr), .alu_src_imm(alu_src_imm), .wb_mem(wb_mem),
      .is_crc(is_crc), .alu_op(alu_op), .imm_type(imm_type)
  );
  assign valid = base_valid || is_m;
  assign uses_rs1 = base_rs1 || is_m;
  assign uses_rs2 = base_rs2 || is_m;
  assign reg_we = base_we || is_m;
endmodule
`default_nettype wire
