`default_nettype none
module decoder (
    input  wire [31:0] insn,
    output reg         valid,
    output reg         uses_rs1,
    output reg         uses_rs2,
    output reg         reg_we,
    output reg         mem_we,
    output reg         mem_re,
    output reg         branch,
    output reg         branch_ne,
    output reg         branch_unsigned,
    output reg         jump,
    output reg         jalr,
    output reg         alu_src_imm,
    output reg         wb_mem,
    output reg         is_crc,
    output reg  [ 4:0] alu_op,
    output reg  [ 2:0] imm_type
);
  localparam OP_R=7'b0110011, OP_I=7'b0010011, OP_LOAD=7'b0000011,
               OP_STORE=7'b0100011, OP_BRANCH=7'b1100011, OP_LUI=7'b0110111,
               OP_AUIPC=7'b0010111, OP_JAL=7'b1101111, OP_JALR=7'b1100111,
               OP_CUSTOM=7'b0001011;
  localparam ALU_ADD=5'd0, ALU_SUB=5'd1, ALU_SLL=5'd2, ALU_SLT=5'd3,
               ALU_SLTU=5'd4, ALU_XOR=5'd5, ALU_SRL=5'd6, ALU_SRA=5'd7,
               ALU_OR=5'd8, ALU_AND=5'd9, ALU_PASS_B=5'd10;
  localparam IMM_I = 3'd0, IMM_S = 3'd1, IMM_B = 3'd2, IMM_U = 3'd3, IMM_J = 3'd4;
  always @* begin
    valid = 1'b0;
    uses_rs1 = 0;
    uses_rs2 = 0;
    reg_we = 0;
    mem_we = 0;
    mem_re = 0;
    branch = 0;
    branch_ne = 0;
    branch_unsigned = 0;
    jump = 0;
    jalr = 0;
    alu_src_imm = 0;
    wb_mem = 0;
    is_crc = 0;
    alu_op = ALU_ADD;
    imm_type = IMM_I;
    case (insn[6:0])
      OP_R: begin
        valid = 1;
        uses_rs1 = 1;
        uses_rs2 = 1;
        reg_we = 1;
        case ({
          insn[30], insn[14:12]
        })
          4'b0000: alu_op = ALU_ADD;
          4'b1000: alu_op = ALU_SUB;
          4'b0001: alu_op = ALU_SLL;
          4'b0010: alu_op = ALU_SLT;
          4'b0011: alu_op = ALU_SLTU;
          4'b0100: alu_op = ALU_XOR;
          4'b0101: alu_op = ALU_SRL;
          4'b1101: alu_op = ALU_SRA;
          4'b0110: alu_op = ALU_OR;
          4'b0111: alu_op = ALU_AND;
          default: valid = 0;
        endcase
      end
      OP_I: begin
        valid = 1;
        uses_rs1 = 1;
        reg_we = 1;
        alu_src_imm = 1;
        imm_type = IMM_I;
        case (insn[14:12])
          3'b000:  alu_op = ALU_ADD;
          3'b010:  alu_op = ALU_SLT;
          3'b011:  alu_op = ALU_SLTU;
          3'b100:  alu_op = ALU_XOR;
          3'b110:  alu_op = ALU_OR;
          3'b111:  alu_op = ALU_AND;
          3'b001:  alu_op = ALU_SLL;
          3'b101:  alu_op = insn[30] ? ALU_SRA : ALU_SRL;
          default: valid = 0;
        endcase
      end
      OP_LOAD: begin
        valid = 1;
        uses_rs1 = 1;
        reg_we = 1;
        mem_re = 1;
        wb_mem = 1;
        alu_src_imm = 1;
        imm_type = IMM_I;
      end
      OP_STORE: begin
        valid = 1;
        uses_rs1 = 1;
        uses_rs2 = 1;
        mem_we = 1;
        alu_src_imm = 1;
        imm_type = IMM_S;
      end
      OP_BRANCH: begin
        valid = 1;
        uses_rs1 = 1;
        uses_rs2 = 1;
        branch = 1;
        imm_type = IMM_B;
        branch_ne = (insn[14:12] == 3'b001) || (insn[14:12] == 3'b101) || (insn[14:12] == 3'b111);
        branch_unsigned = (insn[14:12] == 3'b110) || (insn[14:12] == 3'b111);
        if (!((insn[14:12]==3'b000)||(insn[14:12]==3'b001)||(insn[14:12]==3'b100)||(insn[14:12]==3'b101)||(insn[14:12]==3'b110)||(insn[14:12]==3'b111)))
          valid = 0;
      end
      OP_LUI: begin
        valid = 1;
        reg_we = 1;
        alu_src_imm = 1;
        imm_type = IMM_U;
        alu_op = ALU_PASS_B;
      end
      OP_AUIPC: begin
        valid = 1;
        reg_we = 1;
        alu_src_imm = 1;
        imm_type = IMM_U;
        alu_op = ALU_ADD;
      end
      OP_JAL: begin
        valid = 1;
        reg_we = 1;
        jump = 1;
        imm_type = IMM_J;
      end
      OP_JALR: begin
        valid = (insn[14:12] == 0);
        uses_rs1 = 1;
        reg_we = 1;
        jump = 1;
        jalr = 1;
        alu_src_imm = 1;
        imm_type = IMM_I;
      end
      OP_CUSTOM: begin
        valid = (insn[31:25] == 0 && insn[14:12] == 0);
        uses_rs1 = valid;
        uses_rs2 = valid;
        reg_we = valid;
        is_crc = valid;
      end
      default: begin
      end
    endcase
  end
endmodule
`default_nettype wire
