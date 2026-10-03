`default_nettype none
module tb_machine_mode;
  localparam [31:0] RAM_BASE = 32'h10000000;
  localparam [31:0] TEST_RESULT = 32'h4000000c;
  localparam [31:0] PASS_VALUE = 32'h600d600d;

  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [31:0] imem[0:16383];
  reg [31:0] ram[0:16383];
  integer i;
  integer cycles = 0;
  integer trap_count = 0;
  reg saw_ecall = 0;
  reg saw_breakpoint = 0;
  reg saw_illegal = 0;
  reg saw_instruction_misaligned = 0;
  reg saw_load_misaligned = 0;
  reg saw_store_misaligned = 0;
  reg saw_timer_irq = 0;
  reg saw_software_irq = 0;

  wire [31:0] imem_addr;
  wire [31:0] imem_rdata = (imem_addr[31:16] == 0) ?
      imem[imem_addr[15:2]] : 32'h00000013;
  wire dmem_valid, dmem_we;
  wire [3:0] dmem_wstrb;
  wire [31:0] dmem_addr, dmem_wdata;
  wire ram_sel = (dmem_addr[31:16] == 16'h1000);
  wire clint_sel = (dmem_addr[31:16] == 16'h0200);
  wire [31:0] clint_rdata;
  reg [31:0] dmem_rdata = 32'd0;
  wire machine_timer_irq, machine_software_irq;
  wire retire_valid, retire_rd_we, trap_taken;
  wire [31:0] retire_pc, retire_insn, retire_rd_data, trap_cause;
  wire [4:0] retire_rd;

  rv32_core dut (
      .clk(clk), .rst(rst), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
      .dmem_valid(dmem_valid), .dmem_we(dmem_we), .dmem_wstrb(dmem_wstrb),
      .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
      .dmem_rdata(dmem_rdata), .machine_timer_irq(machine_timer_irq),
      .machine_software_irq(machine_software_irq),
      .retire_valid(retire_valid), .retire_pc(retire_pc),
      .retire_insn(retire_insn), .retire_rd_we(retire_rd_we),
      .retire_rd(retire_rd), .retire_rd_data(retire_rd_data),
      .trap_taken(trap_taken), .trap_cause(trap_cause),
      .event_stall_load(), .event_fwd_ex_count(), .event_fwd_wb_count(),
      .event_flush(), .event_branch(), .event_branch_taken(),
      .event_custom_crc()
  );

  clint timer (
      .clk(clk), .rst(rst), .valid(dmem_valid && clint_sel), .we(dmem_we),
      .wstrb(dmem_wstrb), .addr(dmem_addr), .wdata(dmem_wdata),
      .rdata(clint_rdata), .machine_timer_irq(machine_timer_irq),
      .machine_software_irq(machine_software_irq)
  );

  always #5 clk = ~clk;

  initial begin
    for (i = 0; i < 16384; i = i + 1) begin
      imem[i] = 32'h00000013;
      ram[i] = 32'd0;
    end
    $readmemh("build/hex/machine_test.hex", imem);
    repeat (10) @(posedge clk);
    rst = 1'b0;
  end

  always @(posedge clk) begin
    if (rst) begin
      cycles <= 0;
      trap_count <= 0;
      dmem_rdata <= 32'd0;
    end else begin
      cycles <= cycles + 1;
      if (cycles > 20000) $fatal(1, "machine-mode regression timeout");

      if (trap_taken) begin
        trap_count <= trap_count + 1;
        case (trap_cause)
          32'd0: saw_instruction_misaligned <= 1'b1;
          32'd2: saw_illegal <= 1'b1;
          32'd3: saw_breakpoint <= 1'b1;
          32'd4: saw_load_misaligned <= 1'b1;
          32'd6: saw_store_misaligned <= 1'b1;
          32'd11: saw_ecall <= 1'b1;
          32'h80000003: saw_software_irq <= 1'b1;
          32'h80000007: saw_timer_irq <= 1'b1;
          default: $fatal(1, "unexpected trap cause %08x", trap_cause);
        endcase
      end

      if (dmem_valid && dmem_we && ram_sel) begin
        if (dmem_wstrb[0]) ram[dmem_addr[15:2]][7:0] <= dmem_wdata[7:0];
        if (dmem_wstrb[1]) ram[dmem_addr[15:2]][15:8] <= dmem_wdata[15:8];
        if (dmem_wstrb[2]) ram[dmem_addr[15:2]][23:16] <= dmem_wdata[23:16];
        if (dmem_wstrb[3]) ram[dmem_addr[15:2]][31:24] <= dmem_wdata[31:24];
      end

      if (dmem_valid && !dmem_we)
        dmem_rdata <= clint_sel ? clint_rdata :
            ram_sel ? ram[dmem_addr[15:2]] : 32'd0;

      if (dmem_valid && dmem_we && dmem_addr == TEST_RESULT) begin
        if (dmem_wdata != PASS_VALUE)
          $fatal(1, "machine firmware reported failure %08x", dmem_wdata);
        if (!(saw_ecall && saw_breakpoint && saw_illegal &&
              saw_instruction_misaligned && saw_load_misaligned &&
              saw_store_misaligned && saw_timer_irq && saw_software_irq))
          $fatal(1, "not all required traps were observed");
        if (trap_count != 8)
          $fatal(1, "expected 8 traps, saw %0d", trap_count);
        if (ram[12] != 6 || ram[13] != 1 || ram[14] != 1)
          $fatal(1, "handler mailbox mismatch sync=%0d timer=%0d soft=%0d",
                 ram[12], ram[13], ram[14]);
        $display("MACHINE MODE PASS: traps=%0d mcycle=%0d minstret=%0d",
                 trap_count, dut.csr_mcycle, dut.csr_minstret);
        $finish;
      end
    end
  end
endmodule
`default_nettype wire
