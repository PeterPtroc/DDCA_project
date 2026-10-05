`default_nettype none
module precise_irq_runner #(parameter PC_STYLE = 0) (output reg done = 0);
  reg clk = 0, rst = 1, timer_irq = 0, software_irq = 0;
  reg [31:0] rom [0:127];
  wire [31:0] ia, da, dw, retire_pc, cause;
  wire dv, we, trap, retired;
  reg [31:0] dr = 0, device_value = 32'h55;
  integer writes = 0, reads = 0, traps = 0;
  integer retired_accesses = 0, retire_counts [0:3];
  integer i, offset, irq_kind, pulse, cycles;

  rv32_core #(.CPU_PC_NEXT_STYLE(PC_STYLE)) dut (
      .clk(clk), .rst(rst), .imem_addr(ia), .imem_rdata(rom[ia[8:2]]),
      .dmem_valid(dv), .dmem_we(we), .dmem_wstrb(),
      .dmem_addr(da), .dmem_wdata(dw), .dmem_rdata(dr),
      .machine_timer_irq(timer_irq), .machine_software_irq(software_irq),
      .retire_valid(retired), .retire_pc(retire_pc), .retire_insn(),
      .retire_rd_we(), .retire_rd(), .retire_rd_data(),
      .trap_taken(trap), .trap_cause(cause), .event_stall_load(),
      .event_fwd_ex_count(), .event_fwd_wb_count(), .event_flush(),
      .event_branch(), .event_branch_taken(), .event_custom_crc()
  );
  always #5 clk = ~clk;
  always @(posedge clk) begin
    if (rst) begin
      writes = 0;
      reads = 0;
      traps = 0;
      retired_accesses = 0;
      device_value <= 32'h55;
      dr <= 0;
      for (i = 0; i < 4; i = i + 1) retire_counts[i] = 0;
    end else begin
      if (dv) begin
        if (we) begin
          if (da != 32'h40000000 || dw != 32'h55)
            $fatal(1, "unexpected store address/data");
          writes = writes + 1;
        end else begin
          if (da != 32'h40000004) $fatal(1, "unexpected read address");
          reads = reads + 1;
          dr <= device_value;
          device_value <= 0; // Read-to-clear MMIO.
        end
      end
      if (retired && retire_pc >= 32'h40 && retire_pc <= 32'h4c) begin
        retire_counts[(retire_pc - 32'h40) >> 2] =
            retire_counts[(retire_pc - 32'h40) >> 2] + 1;
        retired_accesses = retired_accesses + 1;
      end
      if (trap) begin
        traps = traps + 1;
        if (cause != (irq_kind == 0 ? 32'h80000007 : 32'h80000003))
          $fatal(1, "wrong interrupt cause %08x", cause);
        if (dv || reads + writes != retired_accesses)
          $fatal(1, "imprecise IRQ style=%0d offset=%0d issued=%0d retired=%0d",
                 PC_STYLE, offset, reads + writes, retired_accesses);
        timer_irq <= 0;
        software_irq <= 0;
      end
    end
  end

  initial begin
    for (i = 0; i < 128; i = i + 1) rom[i] = 32'h00000013;
    rom[0] = 32'h10000293; // addi t0,zero,0x100
    rom[1] = 32'h30529073; // csrw mtvec,t0
    rom[2] = 32'h08800293; // enable MSI and MTI
    rom[3] = 32'h30429073;
    rom[4] = 32'h30046073; // csrsi mstatus,8
    rom[5] = 32'h400002b7;
    rom[6] = 32'h05500313;
    rom[16] = 32'h0062a023; // sw t1,0(t0)
    rom[17] = 32'h0062a023;
    rom[18] = 32'h0042a483; // lw s1,4(t0)
    rom[19] = 32'h0042a503; // lw s2,4(t0)
    rom[20] = 32'h00a489b3; // add s3,s1,s2 (load dependency)
    rom[21] = 32'h0000006f;
    rom[64] = 32'h30200073;
    for (irq_kind = 0; irq_kind < 2; irq_kind = irq_kind + 1)
      for (pulse = 0; pulse < 2; pulse = pulse + 1)
        for (offset = 0; offset < 10; offset = offset + 1) begin
          rst = 1;
          timer_irq = 0;
          software_irq = 0;
          repeat (6) @(negedge clk);
          rst = 0;
          cycles = 0;
          while (!(dut.ifid_valid && dut.ifid_pc == 32'h40) && cycles < 100) begin
            @(negedge clk);
            cycles = cycles + 1;
          end
          if (cycles == 100) $fatal(1, "IRQ test did not reach access stream");
          repeat (offset) @(negedge clk);
          if (irq_kind == 0) timer_irq = 1;
          else software_irq = 1;
          if (pulse) begin
            @(negedge clk);
            timer_irq = 0;
            software_irq = 0;
          end
          repeat (150) @(negedge clk);
          if (writes != 2 || reads != 2 || traps != 1 ||
              dut.rf.regs[9] != 32'h55 || dut.rf.regs[10] != 0 ||
              dut.rf.regs[19] != 32'h55)
            $fatal(1, "IRQ test failed style=%0d kind=%0d pulse=%0d offset=%0d writes=%0d reads=%0d traps=%0d",
                   PC_STYLE, irq_kind, pulse, offset, writes, reads, traps);
          for (i = 0; i < 4; i = i + 1)
            if (retire_counts[i] != 1) $fatal(1, "memory instruction retired twice or lost");
        end
    done = 1;
  end
endmodule

module tb_precise_irq;
  wire done0, done1;
  precise_irq_runner #(.PC_STYLE(0)) style0(done0);
  precise_irq_runner #(.PC_STYLE(1)) style1(done1);
  initial begin
    wait (done0 && done1);
    $display("PRECISE IRQ PASS: 80 cases, MSI/MTI, level/pulse, two PC styles, consecutive stores/read-to-clear loads");
    $finish;
  end
endmodule
`default_nettype wire
