`default_nettype none
module rv32_core #(
    parameter CPU_PC_NEXT_STYLE = 0
) (
    input wire clk,
    input wire rst,
    output wire [31:0] imem_addr,
    input wire [31:0] imem_rdata,
    output wire dmem_valid,
    output wire dmem_we,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input wire [31:0] dmem_rdata,
    output wire retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_insn,
    output wire retire_rd_we,
    output wire [4:0] retire_rd,
    output wire [31:0] retire_rd_data,
    output wire event_stall_load,
    output wire [1:0] event_fwd_ex_count,
    output wire [1:0] event_fwd_wb_count,
    output wire event_flush,
    output wire event_branch,
    output wire event_branch_taken,
    output wire event_custom_crc
);
  localparam ALU_ADD = 5'd0, ALU_SUB = 5'd1, ALU_PASS_B = 5'd10;
  localparam IMM_I   = 3'd0;
  reg [31:0] pc;
  wire [31:0] insn = imem_rdata;
  reg ifid_valid;
  reg [31:0] ifid_pc, ifid_insn;
  wire [4:0] ifid_rs1 = ifid_insn[19:15], ifid_rs2 = ifid_insn[24:20];
  reg idex_valid;
  reg [31:0] idex_pc, idex_insn, idex_rs1_val, idex_rs2_val, idex_imm;
  reg [4:0] idex_rs1, idex_rs2, idex_rd;
  reg
      idex_reg_we,
      idex_mem_we,
      idex_mem_re,
      idex_branch,
      idex_jump,
      idex_jalr,
      idex_alu_src_imm,
      idex_wb_mem,
      idex_is_crc;
  reg [4:0] idex_alu_op;
  reg exmem_valid;
  reg [31:0] exmem_pc, exmem_insn, exmem_alu, exmem_store_data;
  reg [4:0] exmem_rd;
  reg exmem_reg_we, exmem_mem_we, exmem_mem_re, exmem_wb_mem, exmem_is_crc;
  reg memwb_valid;
  reg [31:0] memwb_pc, memwb_insn, memwb_alu, memwb_mem_data;
  reg [4:0] memwb_rd;
  reg memwb_reg_we, memwb_wb_mem, memwb_is_crc;
  wire dec_valid,dec_uses_rs1,dec_uses_rs2,dec_reg_we,dec_mem_we,dec_mem_re,dec_branch,dec_jump,dec_jalr,dec_alu_src_imm,dec_wb_mem,dec_is_crc;
  wire [4:0] dec_alu_op;
  wire [2:0] dec_imm_type;
  decoder dec (
      .insn(ifid_insn),
      .valid(dec_valid),
      .uses_rs1(dec_uses_rs1),
      .uses_rs2(dec_uses_rs2),
      .reg_we(dec_reg_we),
      .mem_we(dec_mem_we),
      .mem_re(dec_mem_re),
      .branch(dec_branch),
      .jump(dec_jump),
      .jalr(dec_jalr),
      .alu_src_imm(dec_alu_src_imm),
      .wb_mem(dec_wb_mem),
      .is_crc(dec_is_crc),
      .alu_op(dec_alu_op),
      .imm_type(dec_imm_type)
  );
  wire [31:0] dec_imm;
  imm_gen ig (
      .insn(ifid_insn),
      .imm_type(dec_imm_type),
      .imm(dec_imm)
  );
  wire [31:0] wb_value = memwb_wb_mem ? memwb_mem_data : memwb_alu;
  wire rf_we = memwb_valid && memwb_reg_we;
  wire [31:0] rf_r1, rf_r2;
  regfile rf (
      .clk(clk),
      .rst(rst),
      .raddr1(ifid_rs1),
      .raddr2(ifid_rs2),
      .rdata1(rf_r1),
      .rdata2(rf_r2),
      .we(rf_we),
      .waddr(memwb_rd),
      .wdata(wb_value)
  );
  wire load_stall;
  hazard_unit hz (
      .ifid_valid(ifid_valid),
      .uses_rs1(dec_uses_rs1),
      .uses_rs2(dec_uses_rs2),
      .ifid_rs1(ifid_rs1),
      .ifid_rs2(ifid_rs2),
      .idex_valid(idex_valid),
      .idex_mem_re(idex_mem_re),
      .idex_rd(idex_rd),
      .load_use_stall(load_stall)
  );
  // Keep the forwarding decision one-hot on the operand datapaths. Encoding
  // it and then decoding it again added a LUT level to the EX-to-PC branch
  // path once the analyzer peripherals increased placement pressure.
  // A load-use consumer is already separated by the interlock, so a valid EX
  // consumer can never need the address value of an EX/MEM load.  Keeping
  // exmem_mem_re in these match terms put that control bit on the full
  // forwarding/branch/PC redirect path.  Removing the redundant qualifier
  // preserves architectural behavior and shortens the 100 MHz critical path.
  wire ex_match_a = exmem_valid && exmem_reg_we &&
                    exmem_rd != 0 && exmem_rd == idex_rs1;
  wire ex_match_b = exmem_valid && exmem_reg_we &&
                    exmem_rd != 0 && exmem_rd == idex_rs2;
  wire wb_match_a = !ex_match_a && memwb_valid && memwb_reg_we &&
                    memwb_rd != 0 && memwb_rd == idex_rs1;
  wire wb_match_b = !ex_match_b && memwb_valid && memwb_reg_we &&
                    memwb_rd != 0 && memwb_rd == idex_rs2;
  wire [1:0] fwd_a = ex_match_a ? 2'd1 : wb_match_a ? 2'd2 : 2'd0;
  wire [1:0] fwd_b = ex_match_b ? 2'd1 : wb_match_b ? 2'd2 : 2'd0;
  wire [31:0] fwd_ex_val = exmem_alu, fwd_wb_val = wb_value;
  wire [31:0] ex_a = ex_match_a ? fwd_ex_val : wb_match_a ? fwd_wb_val : idex_rs1_val;
  wire [31:0] ex_b_reg = ex_match_b ? fwd_ex_val : wb_match_b ? fwd_wb_val : idex_rs2_val;
  wire [15:0] crc_next;
  crc16_unit crc (
      .crc(ex_a[15:0]),
      .data(ex_b_reg[7:0]),
      .next_crc(crc_next)
  );
  wire [31:0] alu_b = idex_alu_src_imm ? idex_imm : ex_b_reg;
  wire [31:0] alu_y;
  alu alu_i (
      .a (idex_jump ? idex_pc : ex_a),
      .b (idex_jump ? 32'd4 : alu_b),
      .op(idex_alu_op),
      .y (alu_y)
  );
  wire [2:0] branch_f3 = idex_insn[14:12];
  wire branch_cmp = (branch_f3==3'b000) ? (ex_a==ex_b_reg) : (branch_f3==3'b001) ? (ex_a!=ex_b_reg) : (branch_f3==3'b100) ? ($signed(
      ex_a
  ) < $signed(
      ex_b_reg
  )) : (branch_f3 == 3'b101) ? ($signed(
      ex_a
  ) >= $signed(
      ex_b_reg
  )) : (branch_f3 == 3'b110) ? (ex_a < ex_b_reg) : (ex_a >= ex_b_reg);
  // JAL has no register dependency and its target is available in ID.  Take
  // that redirect one stage early; JALR and conditional branches still wait
  // for EX because they need forwarded operand values or a comparison.
  wire jal_id_redirect = ifid_valid && dec_valid && dec_jump && !dec_jalr && !load_stall;
  wire [31:0] jal_id_target = ifid_pc + dec_imm;
  wire redirect = idex_valid && ((idex_branch && branch_cmp) ||
      (idex_jump && idex_jalr));
  wire [31:0] redirect_target = idex_jalr ? ((ex_a + idex_imm) & 32'hfffffffe) : (idex_pc + idex_imm);
  wire [31:0] pc_next = redirect ? redirect_target :
      jal_id_redirect ? jal_id_target : load_stall ? pc : pc + 32'd4;
  wire [31:0] ex_result = idex_is_crc ? {16'd0,crc_next} : (idex_jump ? (idex_pc+32'd4) : (idex_alu_op==ALU_ADD && idex_insn[6:0]==7'b0010111 ? idex_pc+idex_imm : alu_y));
  assign imem_addr = pc;
  assign dmem_valid = exmem_valid && (exmem_mem_we || exmem_mem_re);
  assign dmem_we = exmem_valid && exmem_mem_we;
  assign dmem_addr = exmem_alu;
  assign dmem_wdata = exmem_store_data;
  assign retire_valid = memwb_valid;
  assign retire_pc = memwb_pc;
  assign retire_insn = memwb_insn;
  assign retire_rd_we = memwb_valid && memwb_reg_we;
  assign retire_rd = memwb_rd;
  assign retire_rd_data = wb_value;
  assign event_stall_load = load_stall;
  assign event_fwd_ex_count = {1'b0, (fwd_a == 1)} + {1'b0, (fwd_b == 1)};
  assign event_fwd_wb_count = {1'b0, (fwd_a == 2)} + {1'b0, (fwd_b == 2)};
  assign event_flush = redirect || jal_id_redirect;
  assign event_branch = idex_valid && idex_branch;
  assign event_branch_taken = idex_valid && idex_branch && branch_cmp;
  assign event_custom_crc = memwb_valid && memwb_is_crc;
  always @(posedge clk) begin
    if (rst) begin
      pc <= 0;
      ifid_valid <= 0;
      idex_valid <= 0;
      exmem_valid <= 0;
      memwb_valid <= 0;
    end else begin
      if (CPU_PC_NEXT_STYLE != 0) begin
        pc <= pc_next;
      end else begin
        if (redirect) pc <= redirect_target;
        else if (jal_id_redirect) pc <= jal_id_target;
        else if (!load_stall) pc <= pc + 4;
      end
      if (redirect) begin
        ifid_valid <= 0;
        idex_valid <= 0;
      end else if (jal_id_redirect) begin
        // Preserve the JAL itself for EX/WB so its link register retires;
        // discard only the sequential instruction currently in IF.
        ifid_valid <= 0;
        idex_valid <= ifid_valid && dec_valid;
      end else if (load_stall) begin
        idex_valid <= 0;
      end else begin
        ifid_valid <= dec_valid || (ifid_valid == 0 && insn != 0);
        idex_valid <= ifid_valid && dec_valid;
      end
      // Timing-closure note: this payload block originally sat inside the
      // redirect/load-stall else branch. The EX branch result therefore drove
      // the enable/reset logic of hundreds of payload flops and missed 100 MHz
      // setup timing by 0.312 ns. A redirect only needs to clear the valid bits
      // above; invalid payload is don't-care. Only a load stall must hold it.
      if (!load_stall) begin
        ifid_pc <= pc;
        ifid_insn <= insn;
        idex_pc <= ifid_pc;
        idex_insn <= ifid_insn;
        idex_rs1 <= ifid_rs1;
        idex_rs2 <= ifid_rs2;
        idex_rd <= ifid_insn[11:7];
        idex_rs1_val <= rf_r1;
        idex_rs2_val <= rf_r2;
        idex_imm <= dec_imm;
        idex_reg_we <= dec_reg_we;
        idex_mem_we <= dec_mem_we;
        idex_mem_re <= dec_mem_re;
        idex_branch <= dec_branch;
        idex_jump <= dec_jump;
        idex_jalr <= dec_jalr;
        idex_alu_src_imm <= dec_alu_src_imm;
        idex_wb_mem <= dec_wb_mem;
        idex_is_crc <= dec_is_crc;
        idex_alu_op <= dec_alu_op;
      end
      exmem_valid <= idex_valid;
      exmem_pc <= idex_pc;
      exmem_insn <= idex_insn;
      exmem_alu <= ex_result;
      exmem_store_data <= ex_b_reg;
      exmem_rd <= idex_rd;
      exmem_reg_we <= idex_reg_we;
      exmem_mem_we <= idex_mem_we;
      exmem_mem_re <= idex_mem_re;
      exmem_wb_mem <= idex_wb_mem;
      exmem_is_crc <= idex_is_crc;
      memwb_valid <= exmem_valid;
      memwb_pc <= exmem_pc;
      memwb_insn <= exmem_insn;
      memwb_alu <= exmem_alu;
      memwb_mem_data <= dmem_rdata;
      memwb_rd <= exmem_rd;
      memwb_reg_we <= exmem_reg_we;
      memwb_wb_mem <= exmem_wb_mem;
      memwb_is_crc <= exmem_is_crc;
    end
  end
endmodule
`default_nettype wire
