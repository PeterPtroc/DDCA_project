`default_nettype none
module rv32m_control_runner #(parameter PC_STYLE = 0) (output reg done = 0);
  reg clk = 0, rst = 1;
  reg [31:0] rom [0:127];
  wire [31:0] ia, da, dw, cause;
  wire dv, we, trap;
  integer i, test_case, cycles, starts, completions, traps, writes;
  rv32im_core #(.CPU_PC_NEXT_STYLE(PC_STYLE)) dut (
      .clk(clk), .rst(rst), .imem_addr(ia), .imem_rdata(rom[ia[8:2]]),
      .dmem_valid(dv), .dmem_we(we), .dmem_wstrb(), .dmem_addr(da),
      .dmem_wdata(dw), .dmem_rdata(32'd0), .machine_timer_irq(1'b0),
      .machine_software_irq(1'b0), .retire_valid(), .retire_pc(),
      .retire_insn(), .retire_rd_we(), .retire_rd(), .retire_rd_data(),
      .trap_taken(trap), .trap_cause(cause), .event_stall_load(),
      .event_fwd_ex_count(), .event_fwd_wb_count(), .event_flush(),
      .event_branch(), .event_branch_taken(), .event_custom_crc()
  );
  always #5 clk = ~clk;
  always @(posedge clk) begin
    if (rst) begin starts = 0; completions = 0; traps = 0; writes = 0; end
    else begin
      if (dut.m_start) starts = starts + 1;
      if (dut.m_done) completions = completions + 1;
      if (trap) begin
        traps = traps + 1;
        if (cause != (test_case == 0 ? 11 : 2)) $fatal(1, "wrong cancellation trap");
      end
      if (dv) begin
        if (!we || da != 32'h40000000 || dw != 2) $fatal(1, "speculative store escaped M barrier");
        writes = writes + 1;
      end
    end
  end
  initial begin
    for (i = 0; i < 128; i = i + 1) rom[i] = 32'h00000013;
    rom[0] = 32'h10000393; // 将陷阱入口 mtvec 设置为 0x100
    rom[1] = 32'h30539073;
    rom[2] = 32'h00700293; // 将 t0 设置为 7
    rom[3] = 32'h00300313; // 将 t1 设置为 3
    rom[4] = 32'h40000437; // 将 MMIO 基地址写入 s0
    rom[17] = 32'h0262c4b3; // 计算有符号除法：div s1,t0,t1
    rom[18] = 32'h00942023; // 将除法结果写入 MMIO：sw s1,0(s0)
    rom[19] = 32'h0000006f;
    rom[64] = 32'h341023f3; // 读取异常返回地址：csrr t2,mepc
    rom[65] = 32'h00438393;
    rom[66] = 32'h34139073;
    rom[67] = 32'h30200073;
    for (test_case = 0; test_case < 3; test_case = test_case + 1) begin
      rst = 1;
      rom[16] = test_case == 0 ? 32'h00000073 :
                test_case == 1 ? 32'hffffffff : 32'h0000100f;
      repeat (6) @(negedge clk);
      rst = 0;
      repeat (240) @(negedge clk);
      if (starts != 2 || completions != 1 || writes != 1 ||
          traps != (test_case == 2 ? 0 : 1) || dut.rf.regs[9] != 2)
        $fatal(1, "M cancellation failed style=%0d case=%0d starts=%0d done=%0d writes=%0d traps=%0d",
               PC_STYLE, test_case, starts, completions, writes, traps);
    end
    done = 1;
  end
endmodule
module tb_rv32m_control;
  wire done0, done1;
  rv32m_control_runner #(.PC_STYLE(0)) style0(done0);
  rv32m_control_runner #(.PC_STYLE(1)) style1(done1);
  initial begin
    wait(done0 && done1);
    $display("RV32M CONTROL PASS: ECALL, illegal, FENCE.I cancellation in both PC styles");
    $finish;
  end
endmodule
`default_nettype wire
