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
    output wire [3:0] dmem_wstrb,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input wire [31:0] dmem_rdata,
    input wire machine_timer_irq,
    input wire machine_software_irq,
    output wire retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_insn,
    output wire retire_rd_we,
    output wire [4:0] retire_rd,
    output wire [31:0] retire_rd_data,
    output wire trap_taken,
    output wire [31:0] trap_cause,
    output wire event_stall_load,
    output wire [1:0] event_fwd_ex_count,
    output wire [1:0] event_fwd_wb_count,
    output wire event_flush,
    output wire event_branch,
    output wire event_branch_taken,
    output wire event_custom_crc
);
  localparam ALU_ADD = 5'd0;

  localparam [31:0] CAUSE_INSN_MISALIGNED = 32'd0,
                    CAUSE_ILLEGAL         = 32'd2,
                    CAUSE_BREAKPOINT      = 32'd3,
                    CAUSE_LOAD_MISALIGNED = 32'd4,
                    CAUSE_STORE_MISALIGNED= 32'd6,
                    CAUSE_ECALL_M         = 32'd11,
                    CAUSE_MSI             = 32'h80000003,
                    CAUSE_MTI             = 32'h80000007;

  reg [31:0] pc;
  wire [31:0] insn = imem_rdata;

  reg ifid_valid;
  reg [31:0] ifid_pc, ifid_insn;
  wire [4:0] ifid_rs1 = ifid_insn[19:15];
  wire [4:0] ifid_rs2 = ifid_insn[24:20];

  reg idex_valid;
  reg [31:0] idex_pc, idex_insn, idex_rs1_val, idex_rs2_val, idex_imm;
  reg [4:0] idex_rs1, idex_rs2, idex_rd;
  reg [1:0] idex_fwd_a, idex_fwd_b;
  reg idex_reg_we, idex_mem_we, idex_mem_re, idex_branch, idex_jump;
  reg idex_jalr, idex_alu_src_imm, idex_wb_mem, idex_is_crc;
  reg [4:0] idex_alu_op;
  reg idex_exc_valid;
  reg [31:0] idex_exc_cause, idex_exc_tval;
  reg idex_is_csr, idex_csr_imm, idex_csr_we;
  reg [1:0] idex_csr_op;
  reg [11:0] idex_csr_addr;
  reg idex_is_mret, idex_fence_i;

  reg exmem_valid;
  reg [31:0] exmem_pc, exmem_insn, exmem_alu, exmem_store_data;
  reg [31:0] exmem_next_pc;
  reg [4:0] exmem_rd;
  reg exmem_reg_we, exmem_mem_we, exmem_mem_re, exmem_wb_mem, exmem_is_crc;
  reg [2:0] exmem_mem_funct3;
  reg exmem_exc_valid;
  reg [31:0] exmem_exc_cause, exmem_exc_tval;
  reg exmem_csr_we;
  reg [11:0] exmem_csr_addr;
  reg [31:0] exmem_csr_wdata;
  reg exmem_is_mret, exmem_fence_i;

  // The request stage decouples the registered EX address from synchronous
  // BRAM/MMIO reads.  Besides closing timing, this gives each target a full
  // cycle to produce its response before MEM/WB captures it.
  reg mem2_valid;
  reg [31:0] mem2_pc, mem2_insn, mem2_alu;
  reg [31:0] mem2_next_pc;
  reg [4:0] mem2_rd;
  reg mem2_reg_we, mem2_mem_re, mem2_wb_mem, mem2_is_crc;
  reg [2:0] mem2_mem_funct3;
  reg mem2_exc_valid;
  reg [31:0] mem2_exc_cause, mem2_exc_tval;
  reg mem2_csr_we;
  reg [11:0] mem2_csr_addr;
  reg [31:0] mem2_csr_wdata;
  reg mem2_is_mret, mem2_fence_i;

  reg memwb_valid;
  reg [31:0] memwb_pc, memwb_insn, memwb_alu, memwb_mem_data;
  reg [31:0] memwb_next_pc;
  reg [4:0] memwb_rd;
  reg memwb_reg_we, memwb_wb_mem, memwb_is_crc;
  reg memwb_exc_valid;
  reg [31:0] memwb_exc_cause, memwb_exc_tval;
  reg memwb_csr_we;
  reg [11:0] memwb_csr_addr;
  reg [31:0] memwb_csr_wdata;
  reg memwb_is_mret, memwb_fence_i;

  // Machine-mode CSR bank. This core intentionally implements only M-mode.
  reg [31:0] csr_mstatus, csr_mie, csr_mtvec, csr_mscratch;
  reg [31:0] csr_mepc, csr_mcause, csr_mtval;
  reg [63:0] csr_mcycle, csr_minstret;

  function csr_implemented;
    input [11:0] addr;
    begin
      case (addr)
        12'h300, 12'h301, 12'h304, 12'h305, 12'h340, 12'h341,
        12'h342, 12'h343, 12'h344, 12'hb00, 12'hb02, 12'hb80,
        12'hb82, 12'hf14: csr_implemented = 1'b1;
        default: csr_implemented = 1'b0;
      endcase
    end
  endfunction

  function csr_writable;
    input [11:0] addr;
    begin
      case (addr)
        12'h300, 12'h304, 12'h305, 12'h340, 12'h341, 12'h342,
        12'h343, 12'h344, 12'hb00, 12'hb02, 12'hb80, 12'hb82:
          csr_writable = 1'b1;
        default: csr_writable = 1'b0;
      endcase
    end
  endfunction

  function [31:0] csr_read;
    input [11:0] addr;
    begin
      case (addr)
        12'h300: csr_read = csr_mstatus;
        12'h301: csr_read = 32'h40000100; // RV32 + I
        12'h304: csr_read = csr_mie;
        12'h305: csr_read = csr_mtvec;
        12'h340: csr_read = csr_mscratch;
        12'h341: csr_read = csr_mepc;
        12'h342: csr_read = csr_mcause;
        12'h343: csr_read = csr_mtval;
        12'h344: csr_read = {24'd0, machine_timer_irq, 3'd0,
                             machine_software_irq, 3'd0};
        12'hb00: csr_read = csr_mcycle[31:0];
        12'hb80: csr_read = csr_mcycle[63:32];
        12'hb02: csr_read = csr_minstret[31:0];
        12'hb82: csr_read = csr_minstret[63:32];
        12'hf14: csr_read = 32'd0;
        default: csr_read = 32'd0;
      endcase
    end
  endfunction

  function [31:0] csr_sanitize;
    input [11:0] addr;
    input [31:0] value;
    begin
      case (addr)
        12'h300: csr_sanitize = {19'd0, 2'b11, 3'd0, value[7], 3'd0,
                                value[3], 3'd0};
        12'h304: csr_sanitize = {24'd0, value[7], 3'd0, value[3], 3'd0};
        12'h305: csr_sanitize = {value[31:2], 2'b00};
        12'h341: csr_sanitize = {value[31:2], 2'b00};
        12'h344: csr_sanitize = {24'd0, machine_timer_irq, 3'd0,
                                machine_software_irq, 3'd0};
        default: csr_sanitize = value;
      endcase
    end
  endfunction

  function [31:0] load_value;
    input [31:0] word;
    input [1:0] byte_offset;
    input [2:0] funct3;
    reg [31:0] shifted;
    begin
      shifted = word >> ({byte_offset, 3'b000});
      case (funct3)
        3'b000: load_value = {{24{shifted[7]}}, shifted[7:0]};
        3'b001: load_value = {{16{shifted[15]}}, shifted[15:0]};
        3'b010: load_value = word;
        3'b100: load_value = {24'd0, shifted[7:0]};
        3'b101: load_value = {16'd0, shifted[15:0]};
        default: load_value = 32'd0;
      endcase
    end
  endfunction

  wire dec_valid, dec_uses_rs1, dec_uses_rs2, dec_reg_we;
  wire dec_mem_we, dec_mem_re, dec_branch, dec_jump, dec_jalr;
  wire dec_alu_src_imm, dec_wb_mem, dec_is_crc;
  wire [4:0] dec_alu_op;
  wire [2:0] dec_imm_type;
  decoder dec (
      .insn(ifid_insn), .valid(dec_valid), .uses_rs1(dec_uses_rs1),
      .uses_rs2(dec_uses_rs2), .reg_we(dec_reg_we), .mem_we(dec_mem_we),
      .mem_re(dec_mem_re), .branch(dec_branch), .jump(dec_jump),
      .jalr(dec_jalr), .alu_src_imm(dec_alu_src_imm), .wb_mem(dec_wb_mem),
      .is_crc(dec_is_crc), .alu_op(dec_alu_op), .imm_type(dec_imm_type)
  );

  wire [31:0] dec_imm;
  imm_gen ig (.insn(ifid_insn), .imm_type(dec_imm_type), .imm(dec_imm));

  wire id_is_system = (ifid_insn[6:0] == 7'b1110011);
  wire id_is_csr = id_is_system && (ifid_insn[14:12] != 3'b000);
  wire id_csr_imm = id_is_csr && ifid_insn[14];
  wire id_csr_we = id_is_csr &&
      ((ifid_insn[13:12] == 2'b01) || (ifid_insn[19:15] != 0));
  wire id_csr_bad = id_is_csr &&
      (!csr_implemented(ifid_insn[31:20]) ||
       (id_csr_we && !csr_writable(ifid_insn[31:20])));
  wire id_ecall = (ifid_insn == 32'h00000073);
  wire id_ebreak = (ifid_insn == 32'h00100073);
  wire id_mret = (ifid_insn == 32'h30200073);
  wire id_fence_i = (ifid_insn == 32'h0000100f);
  wire id_illegal = !dec_valid || id_csr_bad;
  wire id_exc_valid = id_illegal || id_ecall || id_ebreak;
  wire [31:0] id_exc_cause = id_illegal ? CAUSE_ILLEGAL :
      id_ebreak ? CAUSE_BREAKPOINT : CAUSE_ECALL_M;
  wire [31:0] id_exc_tval = id_illegal ? ifid_insn : 32'd0;

  wire [31:0] wb_value = memwb_wb_mem ? memwb_mem_data : memwb_alu;
  wire rf_we = memwb_valid && memwb_reg_we && !memwb_exc_valid;
  wire [31:0] rf_r1, rf_r2;
  regfile rf (
      .clk(clk), .rst(rst), .raddr1(ifid_rs1), .raddr2(ifid_rs2),
      .rdata1(rf_r1), .rdata2(rf_r2), .we(rf_we),
      .waddr(memwb_rd), .wdata(wb_value)
  );

  wire load_stall;
  hazard_unit hz (
      .ifid_valid(ifid_valid), .uses_rs1(dec_uses_rs1),
      .uses_rs2(dec_uses_rs2), .ifid_rs1(ifid_rs1), .ifid_rs2(ifid_rs2),
      .idex_valid(idex_valid), .idex_mem_re(idex_mem_re), .idex_rd(idex_rd),
      .exmem_valid(exmem_valid), .exmem_mem_re(exmem_mem_re),
      .exmem_rd(exmem_rd),
      .load_use_stall(load_stall)
  );

  // Resolve forwarding selections in ID, one cycle before the operand muxes.
  // This removes register-number comparators from the EX ALU/branch critical
  // path while retaining both EX/MEM and MEM/WB forwarding behavior.
  wire id_match_ex_a = idex_valid && idex_reg_we && idex_rd != 0 &&
                       idex_rd == ifid_rs1;
  wire id_match_ex_b = idex_valid && idex_reg_we && idex_rd != 0 &&
                       idex_rd == ifid_rs2;
  wire id_match_mem_a = !id_match_ex_a && exmem_valid && !exmem_exc_valid &&
                       exmem_reg_we && exmem_rd != 0 && exmem_rd == ifid_rs1;
  wire id_match_mem_b = !id_match_ex_b && exmem_valid && !exmem_exc_valid &&
                       exmem_reg_we && exmem_rd != 0 && exmem_rd == ifid_rs2;
  wire id_match_wb_a = !id_match_ex_a && !id_match_mem_a &&
                       mem2_valid && !mem2_exc_valid && mem2_reg_we &&
                       mem2_rd != 0 && mem2_rd == ifid_rs1;
  wire id_match_wb_b = !id_match_ex_b && !id_match_mem_b &&
                       mem2_valid && !mem2_exc_valid && mem2_reg_we &&
                       mem2_rd != 0 && mem2_rd == ifid_rs2;
  wire [1:0] id_fwd_a = id_match_ex_a ? 2'd1 :
      id_match_mem_a ? 2'd2 : id_match_wb_a ? 2'd3 : 2'd0;
  wire [1:0] id_fwd_b = id_match_ex_b ? 2'd1 :
      id_match_mem_b ? 2'd2 : id_match_wb_b ? 2'd3 : 2'd0;
  wire [1:0] fwd_a = idex_fwd_a;
  wire [1:0] fwd_b = idex_fwd_b;
  wire [31:0] ex_a = (fwd_a == 1) ? exmem_alu :
                     (fwd_a == 2) ? mem2_alu :
                     (fwd_a == 3) ? wb_value : idex_rs1_val;
  wire [31:0] ex_b_reg = (fwd_b == 1) ? exmem_alu :
                         (fwd_b == 2) ? mem2_alu :
                         (fwd_b == 3) ? wb_value : idex_rs2_val;

  wire [15:0] crc_next;
  crc16_unit crc (.crc(ex_a[15:0]), .data(ex_b_reg[7:0]), .next_crc(crc_next));
  wire [31:0] alu_b = idex_alu_src_imm ? idex_imm : ex_b_reg;
  wire [31:0] alu_y;
  alu alu_i (
      .a(idex_jump ? idex_pc : ex_a),
      .b(idex_jump ? 32'd4 : alu_b), .op(idex_alu_op), .y(alu_y)
  );

  wire [2:0] branch_f3 = idex_insn[14:12];
  wire branch_cmp = (branch_f3 == 3'b000) ? (ex_a == ex_b_reg) :
      (branch_f3 == 3'b001) ? (ex_a != ex_b_reg) :
      (branch_f3 == 3'b100) ? ($signed(ex_a) < $signed(ex_b_reg)) :
      (branch_f3 == 3'b101) ? ($signed(ex_a) >= $signed(ex_b_reg)) :
      (branch_f3 == 3'b110) ? (ex_a < ex_b_reg) : (ex_a >= ex_b_reg);
  wire ex_control_taken = (idex_branch && branch_cmp) || idex_jump;
  wire [31:0] ex_control_target = idex_jalr ?
      ((ex_a + idex_imm) & 32'hfffffffe) : (idex_pc + idex_imm);
  wire ex_insn_misaligned = idex_valid && ex_control_taken &&
                            (ex_control_target[1:0] != 2'b00);
  wire [31:0] ex_address = alu_y;
  wire ex_load_misaligned = idex_valid && idex_mem_re &&
      (((idex_insn[14:12] == 3'b001 || idex_insn[14:12] == 3'b101) &&
        ex_address[0]) ||
       ((idex_insn[14:12] == 3'b010) && (ex_address[1:0] != 0)));
  wire ex_store_misaligned = idex_valid && idex_mem_we &&
      (((idex_insn[14:12] == 3'b001) && ex_address[0]) ||
       ((idex_insn[14:12] == 3'b010) && (ex_address[1:0] != 0)));
  wire ex_new_exc = !idex_exc_valid &&
                    (ex_insn_misaligned || ex_load_misaligned ||
                     ex_store_misaligned);
  wire ex_exc_valid = idex_exc_valid || ex_new_exc;
  wire [31:0] ex_exc_cause = idex_exc_valid ? idex_exc_cause :
      ex_insn_misaligned ? CAUSE_INSN_MISALIGNED :
      ex_load_misaligned ? CAUSE_LOAD_MISALIGNED : CAUSE_STORE_MISALIGNED;
  wire [31:0] ex_exc_tval = idex_exc_valid ? idex_exc_tval :
      ex_insn_misaligned ? ex_control_target : ex_address;

  wire [31:0] csr_forwarded_read =
      (exmem_valid && !exmem_exc_valid && exmem_csr_we &&
       exmem_csr_addr == idex_csr_addr) ? exmem_csr_wdata :
      (mem2_valid && !mem2_exc_valid && mem2_csr_we &&
       mem2_csr_addr == idex_csr_addr) ? mem2_csr_wdata :
      (memwb_valid && !memwb_exc_valid && memwb_csr_we &&
       memwb_csr_addr == idex_csr_addr) ? memwb_csr_wdata :
      csr_read(idex_csr_addr);
  wire [31:0] ex_csr_source = idex_csr_imm ? {27'd0, idex_rs1} : ex_a;
  wire [31:0] ex_csr_raw = (idex_csr_op == 2'b01) ? ex_csr_source :
      (idex_csr_op == 2'b10) ? (csr_forwarded_read | ex_csr_source) :
      (csr_forwarded_read & ~ex_csr_source);
  wire [31:0] ex_csr_wdata = csr_sanitize(idex_csr_addr, ex_csr_raw);

  wire [31:0] ex_regular_result = idex_is_crc ? {16'd0, crc_next} :
      (idex_jump ? (idex_pc + 32'd4) :
       (idex_alu_op == ALU_ADD && idex_insn[6:0] == 7'b0010111) ?
        idex_pc + idex_imm : alu_y);
  wire [31:0] ex_result = idex_is_csr ? csr_forwarded_read : ex_regular_result;
  wire [31:0] ex_next_pc = ex_control_taken ? ex_control_target : idex_pc + 32'd4;

  wire [31:0] effective_mstatus =
      (memwb_valid && !memwb_exc_valid && memwb_csr_we &&
       memwb_csr_addr == 12'h300) ? memwb_csr_wdata : csr_mstatus;
  wire [31:0] effective_mie =
      (memwb_valid && !memwb_exc_valid && memwb_csr_we &&
       memwb_csr_addr == 12'h304) ? memwb_csr_wdata : csr_mie;
  wire [31:0] effective_mtvec =
      (memwb_valid && !memwb_exc_valid && memwb_csr_we &&
       memwb_csr_addr == 12'h305) ? memwb_csr_wdata : csr_mtvec;
  wire irq_enabled = effective_mstatus[3];
  wire software_irq_pending = irq_enabled && effective_mie[3] && machine_software_irq;
  wire timer_irq_pending = irq_enabled && effective_mie[7] && machine_timer_irq;
  wire any_irq_pending = software_irq_pending || timer_irq_pending;
  wire take_exception = memwb_valid && memwb_exc_valid;
  wire take_interrupt = memwb_valid && !memwb_exc_valid && !memwb_is_mret &&
                        any_irq_pending;
  wire take_mret = memwb_valid && !memwb_exc_valid && memwb_is_mret;
  wire take_fence_i = memwb_valid && !memwb_exc_valid && memwb_fence_i;
  wire commit_redirect = take_exception || take_interrupt || take_mret || take_fence_i;
  wire [31:0] interrupt_cause = software_irq_pending ? CAUSE_MSI : CAUSE_MTI;
  wire [31:0] commit_target = (take_exception || take_interrupt) ? effective_mtvec :
      take_mret ? csr_mepc : memwb_next_pc;

  wire [31:0] jal_id_target = ifid_pc + dec_imm;
  wire jal_id_redirect = ifid_valid && dec_valid && dec_jump && !dec_jalr &&
      !id_exc_valid && !load_stall && (jal_id_target[1:0] == 2'b00);
  wire redirect = idex_valid && !ex_exc_valid &&
                  ((idex_branch && branch_cmp) || (idex_jump && idex_jalr));
  wire [31:0] redirect_target = ex_control_target;
  wire [31:0] pc_next = commit_redirect ? commit_target :
      redirect ? redirect_target : jal_id_redirect ? jal_id_target :
      load_stall ? pc : pc + 32'd4;

  wire [3:0] store_strobe =
      (exmem_mem_funct3 == 3'b000) ? (4'b0001 << exmem_alu[1:0]) :
      (exmem_mem_funct3 == 3'b001) ? (4'b0011 << exmem_alu[1:0]) : 4'b1111;
  wire [31:0] shifted_store_data =
      exmem_store_data << ({exmem_alu[1:0], 3'b000});
  // Data requests are launched from the registered EX/MEM stage.  The
  // synchronous target samples that address at the following edge; MEM2 holds
  // the matching metadata while the response gets a full cycle to MEM/WB.
  // Stores are allowed to take effect only when no older instruction can
  // still redirect or trap.
  wire older_side_effect_barrier =
      (mem2_valid && (mem2_exc_valid || mem2_is_mret || mem2_fence_i));

  assign imem_addr = pc;
  assign dmem_valid = exmem_valid && !exmem_exc_valid && !commit_redirect &&
                      !older_side_effect_barrier &&
                      (exmem_mem_we || exmem_mem_re);
  assign dmem_we = dmem_valid && exmem_mem_we;
  assign dmem_wstrb = dmem_we ? store_strobe : 4'b0000;
  assign dmem_addr = exmem_alu;
  assign dmem_wdata = shifted_store_data;

  assign retire_valid = memwb_valid && !memwb_exc_valid;
  assign retire_pc = memwb_pc;
  assign retire_insn = memwb_insn;
  assign retire_rd_we = retire_valid && memwb_reg_we;
  assign retire_rd = memwb_rd;
  assign retire_rd_data = wb_value;
  assign trap_taken = take_exception || take_interrupt;
  assign trap_cause = take_exception ? memwb_exc_cause : interrupt_cause;
  assign event_stall_load = load_stall;
  assign event_fwd_ex_count = {1'b0, (fwd_a == 1)} + {1'b0, (fwd_b == 1)};
  assign event_fwd_wb_count =
      {1'b0, (fwd_a == 2 || fwd_a == 3)} +
      {1'b0, (fwd_b == 2 || fwd_b == 3)};
  assign event_flush = commit_redirect || redirect || jal_id_redirect;
  assign event_branch = idex_valid && !ex_exc_valid && idex_branch;
  assign event_branch_taken = event_branch && branch_cmp;
  assign event_custom_crc = retire_valid && memwb_is_crc;

  always @(posedge clk) begin
    if (rst) begin
      pc <= 32'd0;
      ifid_valid <= 1'b0;
      idex_valid <= 1'b0;
      exmem_valid <= 1'b0;
      mem2_valid <= 1'b0;
      memwb_valid <= 1'b0;
      csr_mstatus <= 32'd0;
      csr_mie <= 32'd0;
      csr_mtvec <= 32'd0;
      csr_mscratch <= 32'd0;
      csr_mepc <= 32'd0;
      csr_mcause <= 32'd0;
      csr_mtval <= 32'd0;
      csr_mcycle <= 64'd0;
      csr_minstret <= 64'd0;
    end else begin
      csr_mcycle <= csr_mcycle + 64'd1;
      if (retire_valid) csr_minstret <= csr_minstret + 64'd1;

      if (memwb_valid && !memwb_exc_valid && memwb_csr_we) begin
        case (memwb_csr_addr)
          12'h300: csr_mstatus <= memwb_csr_wdata;
          12'h304: csr_mie <= memwb_csr_wdata;
          12'h305: csr_mtvec <= memwb_csr_wdata;
          12'h340: csr_mscratch <= memwb_csr_wdata;
          12'h341: csr_mepc <= memwb_csr_wdata;
          12'h342: csr_mcause <= memwb_csr_wdata;
          12'h343: csr_mtval <= memwb_csr_wdata;
          12'hb00: csr_mcycle[31:0] <= memwb_csr_wdata;
          12'hb80: csr_mcycle[63:32] <= memwb_csr_wdata;
          12'hb02: csr_minstret[31:0] <= memwb_csr_wdata;
          12'hb82: csr_minstret[63:32] <= memwb_csr_wdata;
          default: ; // mip live bits are supplied by the platform.
        endcase
      end

      if (take_exception || take_interrupt) begin
        csr_mepc <= take_exception ? memwb_pc : memwb_next_pc;
        csr_mcause <= take_exception ? memwb_exc_cause : interrupt_cause;
        csr_mtval <= take_exception ? memwb_exc_tval : 32'd0;
        csr_mstatus <= {19'd0, 2'b11, 3'd0, effective_mstatus[3],
                        3'd0, 1'b0, 3'd0};
      end else if (take_mret) begin
        csr_mstatus <= {19'd0, 2'b11, 3'd0, 1'b1, 3'd0,
                        csr_mstatus[7], 3'd0};
      end

      if (commit_redirect) begin
        pc <= commit_target;
        ifid_valid <= 1'b0;
        idex_valid <= 1'b0;
        exmem_valid <= 1'b0;
        mem2_valid <= 1'b0;
        memwb_valid <= 1'b0;
      end else begin
        if (CPU_PC_NEXT_STYLE != 0) begin
          pc <= pc_next;
        end else begin
          if (redirect) pc <= redirect_target;
          else if (jal_id_redirect) pc <= jal_id_target;
          else if (!load_stall) pc <= pc + 32'd4;
        end

        if (redirect) begin
          ifid_valid <= 1'b0;
          idex_valid <= 1'b0;
        end else if (jal_id_redirect) begin
          ifid_valid <= 1'b0;
          idex_valid <= ifid_valid;
        end else if (load_stall) begin
          idex_valid <= 1'b0;
        end else begin
          ifid_valid <= 1'b1;
          idex_valid <= ifid_valid;
        end

        if (!load_stall) begin
          ifid_pc <= pc;
          ifid_insn <= insn;
          idex_pc <= ifid_pc;
          idex_insn <= ifid_insn;
          idex_rs1 <= ifid_rs1;
          idex_rs2 <= ifid_rs2;
          idex_rd <= ifid_insn[11:7];
          idex_fwd_a <= id_fwd_a;
          idex_fwd_b <= id_fwd_b;
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
          idex_exc_valid <= id_exc_valid;
          idex_exc_cause <= id_exc_cause;
          idex_exc_tval <= id_exc_tval;
          idex_is_csr <= id_is_csr;
          idex_csr_imm <= id_csr_imm;
          idex_csr_we <= id_csr_we;
          idex_csr_op <= ifid_insn[13:12];
          idex_csr_addr <= ifid_insn[31:20];
          idex_is_mret <= id_mret;
          idex_fence_i <= id_fence_i;
        end

        exmem_valid <= idex_valid;
        exmem_pc <= idex_pc;
        exmem_insn <= idex_insn;
        exmem_alu <= ex_result;
        exmem_store_data <= ex_b_reg;
        exmem_next_pc <= ex_next_pc;
        exmem_rd <= idex_rd;
        exmem_reg_we <= idex_reg_we;
        exmem_mem_we <= idex_mem_we;
        exmem_mem_re <= idex_mem_re;
        exmem_wb_mem <= idex_wb_mem;
        exmem_is_crc <= idex_is_crc;
        exmem_mem_funct3 <= idex_insn[14:12];
        exmem_exc_valid <= ex_exc_valid;
        exmem_exc_cause <= ex_exc_cause;
        exmem_exc_tval <= ex_exc_tval;
        exmem_csr_we <= idex_is_csr && idex_csr_we;
        exmem_csr_addr <= idex_csr_addr;
        exmem_csr_wdata <= ex_csr_wdata;
        exmem_is_mret <= idex_is_mret;
        exmem_fence_i <= idex_fence_i;

        mem2_valid <= exmem_valid;
        mem2_pc <= exmem_pc;
        mem2_insn <= exmem_insn;
        mem2_alu <= exmem_alu;
        mem2_next_pc <= exmem_next_pc;
        mem2_rd <= exmem_rd;
        mem2_reg_we <= exmem_reg_we;
        mem2_mem_re <= exmem_mem_re;
        mem2_wb_mem <= exmem_wb_mem;
        mem2_is_crc <= exmem_is_crc;
        mem2_mem_funct3 <= exmem_mem_funct3;
        mem2_exc_valid <= exmem_exc_valid;
        mem2_exc_cause <= exmem_exc_cause;
        mem2_exc_tval <= exmem_exc_tval;
        mem2_csr_we <= exmem_csr_we;
        mem2_csr_addr <= exmem_csr_addr;
        mem2_csr_wdata <= exmem_csr_wdata;
        mem2_is_mret <= exmem_is_mret;
        mem2_fence_i <= exmem_fence_i;

        memwb_valid <= mem2_valid;
        memwb_pc <= mem2_pc;
        memwb_insn <= mem2_insn;
        memwb_alu <= mem2_alu;
        memwb_mem_data <= load_value(dmem_rdata, mem2_alu[1:0],
                                     mem2_mem_funct3);
        memwb_next_pc <= mem2_next_pc;
        memwb_rd <= mem2_rd;
        memwb_reg_we <= mem2_reg_we;
        memwb_wb_mem <= mem2_wb_mem;
        memwb_is_crc <= mem2_is_crc;
        memwb_exc_valid <= mem2_exc_valid;
        memwb_exc_cause <= mem2_exc_cause;
        memwb_exc_tval <= mem2_exc_tval;
        memwb_csr_we <= mem2_csr_we;
        memwb_csr_addr <= mem2_csr_addr;
        memwb_csr_wdata <= mem2_csr_wdata;
        memwb_is_mret <= mem2_is_mret;
        memwb_fence_i <= mem2_fence_i;
      end
    end
  end
endmodule
`default_nettype wire
