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
               OP_MISC_MEM=7'b0001111, OP_SYSTEM=7'b1110011,
               OP_CUSTOM=7'b0001011;
  localparam ALU_ADD=5'd0, ALU_SUB=5'd1, ALU_SLL=5'd2, ALU_SLT=5'd3,
               ALU_SLTU=5'd4, ALU_XOR=5'd5, ALU_SRL=5'd6, ALU_SRA=5'd7,
               ALU_OR=5'd8, ALU_AND=5'd9, ALU_PASS_B=5'd10;
  localparam IMM_I = 3'd0, IMM_S = 3'd1, IMM_B = 3'd2, IMM_U = 3'd3, IMM_J = 3'd4;

  always @* begin
    valid = 1'b0;
    uses_rs1 = 1'b0;
    uses_rs2 = 1'b0;
    reg_we = 1'b0;
    mem_we = 1'b0;
    mem_re = 1'b0;
    branch = 1'b0;
    jump = 1'b0;
    jalr = 1'b0;
    alu_src_imm = 1'b0;
    wb_mem = 1'b0;
    is_crc = 1'b0;
    alu_op = ALU_ADD;
    imm_type = IMM_I;
    case (insn[6:0])
      OP_R: begin
        uses_rs1 = 1'b1;
        uses_rs2 = 1'b1;
        reg_we = 1'b1;
        case ({insn[31:25], insn[14:12]})
          10'b0000000_000: begin valid = 1'b1; alu_op = ALU_ADD;  end
          10'b0100000_000: begin valid = 1'b1; alu_op = ALU_SUB;  end
          10'b0000000_001: begin valid = 1'b1; alu_op = ALU_SLL;  end
          10'b0000000_010: begin valid = 1'b1; alu_op = ALU_SLT;  end
          10'b0000000_011: begin valid = 1'b1; alu_op = ALU_SLTU; end
          10'b0000000_100: begin valid = 1'b1; alu_op = ALU_XOR;  end
          10'b0000000_101: begin valid = 1'b1; alu_op = ALU_SRL;  end
          10'b0100000_101: begin valid = 1'b1; alu_op = ALU_SRA;  end
          10'b0000000_110: begin valid = 1'b1; alu_op = ALU_OR;   end
          10'b0000000_111: begin valid = 1'b1; alu_op = ALU_AND;  end
          default: valid = 1'b0;
        endcase
      end
      OP_I: begin
        uses_rs1 = 1'b1;
        reg_we = 1'b1;
        alu_src_imm = 1'b1;
        imm_type = IMM_I;
        case (insn[14:12])
          3'b000: begin valid = 1'b1; alu_op = ALU_ADD;  end
          3'b010: begin valid = 1'b1; alu_op = ALU_SLT;  end
          3'b011: begin valid = 1'b1; alu_op = ALU_SLTU; end
          3'b100: begin valid = 1'b1; alu_op = ALU_XOR;  end
          3'b110: begin valid = 1'b1; alu_op = ALU_OR;   end
          3'b111: begin valid = 1'b1; alu_op = ALU_AND;  end
          3'b001: begin
            valid = (insn[31:25] == 7'b0000000);
            alu_op = ALU_SLL;
          end
          3'b101: begin
            valid = (insn[31:25] == 7'b0000000) ||
                    (insn[31:25] == 7'b0100000);
            alu_op = insn[30] ? ALU_SRA : ALU_SRL;
          end
          default: valid = 1'b0;
        endcase
      end
      OP_LOAD: begin
        valid = (insn[14:12] == 3'b000) || (insn[14:12] == 3'b001) ||
                (insn[14:12] == 3'b010) || (insn[14:12] == 3'b100) ||
                (insn[14:12] == 3'b101);
        uses_rs1 = 1'b1;
        reg_we = 1'b1;
        mem_re = 1'b1;
        wb_mem = 1'b1;
        alu_src_imm = 1'b1;
        imm_type = IMM_I;
      end
      OP_STORE: begin
        valid = (insn[14:12] == 3'b000) || (insn[14:12] == 3'b001) ||
                (insn[14:12] == 3'b010);
        uses_rs1 = 1'b1;
        uses_rs2 = 1'b1;
        mem_we = 1'b1;
        alu_src_imm = 1'b1;
        imm_type = IMM_S;
      end
      OP_BRANCH: begin
        valid = (insn[14:12] == 3'b000) || (insn[14:12] == 3'b001) ||
                (insn[14:12] == 3'b100) || (insn[14:12] == 3'b101) ||
                (insn[14:12] == 3'b110) || (insn[14:12] == 3'b111);
        uses_rs1 = 1'b1;
        uses_rs2 = 1'b1;
        branch = 1'b1;
        imm_type = IMM_B;
      end
      OP_LUI: begin
        valid = 1'b1;
        reg_we = 1'b1;
        alu_src_imm = 1'b1;
        imm_type = IMM_U;
        alu_op = ALU_PASS_B;
      end
      OP_AUIPC: begin
        valid = 1'b1;
        reg_we = 1'b1;
        alu_src_imm = 1'b1;
        imm_type = IMM_U;
        alu_op = ALU_ADD;
      end
      OP_JAL: begin
        valid = 1'b1;
        reg_we = 1'b1;
        jump = 1'b1;
        imm_type = IMM_J;
      end
      OP_JALR: begin
        valid = (insn[14:12] == 3'b000);
        uses_rs1 = 1'b1;
        reg_we = 1'b1;
        jump = 1'b1;
        jalr = 1'b1;
        alu_src_imm = 1'b1;
        imm_type = IMM_I;
      end
      OP_MISC_MEM: begin
        valid = ((insn[14:12] == 3'b000) && (insn[11:7] == 0) &&
                 (insn[19:15] == 0)) || (insn == 32'h0000100f);
      end
      OP_SYSTEM: begin
        if (insn[14:12] == 3'b000) begin
          valid = (insn == 32'h00000073) || (insn == 32'h00100073) ||
                  (insn == 32'h30200073);
        end else begin
          valid = (insn[14:12] == 3'b001) || (insn[14:12] == 3'b010) ||
                  (insn[14:12] == 3'b011) || (insn[14:12] == 3'b101) ||
                  (insn[14:12] == 3'b110) || (insn[14:12] == 3'b111);
          uses_rs1 = valid && !insn[14] && (insn[19:15] != 0);
          reg_we = valid;
        end
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
