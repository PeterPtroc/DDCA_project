`default_nettype none
module rv32m_wait_irq_runner #(parameter PC_STYLE = 0) (output reg done = 0);
  reg clk = 0, rst = 1, timer_irq = 0, software_irq = 0;
  reg [31:0] rom [0:127];
  wire [31:0] ia, da, dw, retire_pc, cause;
  wire dv, we, trap, retired;
  reg [31:0] dr = 0, device_value = 32'h55;
  reg [3:0] memory_delay = 0;
  reg [31:0] pending_addr, pending_data;
  reg pending_we;
  wire memory_ready = memory_delay == 1;
  integer writes = 0, reads = 0, traps = 0, retire_counts [0:6];
  integer i, offset, irq_kind, pulse, cycles, cases = 0;
  rv32im_mem_core #(.CPU_PC_NEXT_STYLE(PC_STYLE)) dut (
      .clk(clk), .rst(rst), .imem_addr(ia), .imem_rdata(rom[ia[8:2]]),
      .dmem_valid(dv), .dmem_we(we), .dmem_wstrb(),
      .dmem_addr(da), .dmem_wdata(dw), .dmem_rdata(dr),
      .dmem_ready(memory_ready), .dmem_error(1'b0),
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
      writes = 0; reads = 0; traps = 0;
      device_value <= 32'h55;
      dr <= 0;
      memory_delay <= 0;
      for (i = 0; i < 7; i = i + 1) retire_counts[i] = 0;
    end else begin
      if (dv && memory_delay == 0) begin
        memory_delay <= 3 + offset % 5;
        pending_addr <= da;
        pending_data <= dw;
        pending_we <= we;
      end else if (memory_delay > 1) memory_delay <= memory_delay - 1'b1;
      else if (memory_ready) memory_delay <= 0;
      if (memory_delay != 0 && (!dv || da !== pending_addr || dw !== pending_data || we !== pending_we))
        $fatal(1, "IRQ changed or abandoned a pending memory transaction");
      if (dv && memory_ready) begin
        if (we) begin
          if (da != 32'h40000000 || dw != 32'h55) $fatal(1, "unexpected M stream store");
          writes = writes + 1;
        end else begin
          if (da != 32'h40000004) $fatal(1, "unexpected M stream load");
          reads = reads + 1;
          dr <= device_value;
          device_value <= 0;
        end
      end
      if (retired && retire_pc >= 32'h40 && retire_pc <= 32'h58)
        retire_counts[(retire_pc - 32'h40) >> 2] = retire_counts[(retire_pc - 32'h40) >> 2] + 1;
      if (trap) begin
        traps = traps + 1;
        if (cause != (irq_kind == 0 ? 32'h80000007 : 32'h80000003)) $fatal(1, "wrong M IRQ cause");
        if (dv || reads + writes != retire_counts[0] + retire_counts[1] + retire_counts[4] + retire_counts[5])
          $fatal(1, "M IRQ crossed an unretired side effect");
        timer_irq <= 0;
        software_irq <= 0;
      end
    end
  end
  initial begin
    for (i = 0; i < 128; i = i + 1) rom[i] = 32'h00000013;
    rom[0] = 32'h10000293;
    rom[1] = 32'h30529073;
    rom[2] = 32'h08800293;
    rom[3] = 32'h30429073;
    rom[4] = 32'h30046073;
    rom[5] = 32'h400002b7;
    rom[6] = 32'h05500313;
    rom[16] = 32'h0062a023; // 将 t1 写入 t0 指向的地址：sw t1,0(t0)
    rom[17] = 32'h0042a483; // 从读取后清零的寄存器加载：lw s1,4(t0)
    rom[18] = 32'h0264c933; // 执行有符号除法，结果为 1：div s2,s1,t1
    rom[19] = 32'h026909b3; // 执行乘法，结果为 0x55：mul s3,s2,t1
    rom[20] = 32'h0132a023; // 存储依赖乘除法单元结果的数据：sw s3,0(t0)
    rom[21] = 32'h0042aa03; // 再次加载已清零的寄存器，结果为 0：lw s4,4(t0)
    rom[22] = 32'h01448ab3; // 执行加法，结果为 0x55：add s5,s1,s4
    rom[23] = 32'h0000006f;
    rom[64] = 32'h30200073;
    for (irq_kind = 0; irq_kind < 2; irq_kind = irq_kind + 1)
      for (pulse = 0; pulse < 2; pulse = pulse + 1)
        for (offset = 0; offset < 81; offset = offset + 1) begin
          rst = 1; timer_irq = 0; software_irq = 0;
          repeat (6) @(negedge clk);
          rst = 0;
          cycles = 0;
          while (!(dut.ifid_valid && dut.ifid_pc == 32'h40) && cycles < 100) begin
            @(negedge clk); cycles = cycles + 1;
          end
          if (cycles == 100) $fatal(1, "M IRQ stream did not start");
          repeat (offset) @(negedge clk);
          if (irq_kind == 0) timer_irq = 1; else software_irq = 1;
          if (pulse) begin
            @(negedge clk); timer_irq = 0; software_irq = 0;
          end
          repeat (180) @(negedge clk);
          if (writes != 2 || reads != 2 || traps != 1 ||
              dut.rf.regs[9] != 32'h55 || dut.rf.regs[18] != 1 ||
              dut.rf.regs[19] != 32'h55 || dut.rf.regs[20] != 0 || dut.rf.regs[21] != 32'h55)
            $fatal(1, "M IRQ failed style=%0d kind=%0d pulse=%0d offset=%0d writes=%0d reads=%0d traps=%0d",
                   PC_STYLE, irq_kind, pulse, offset, writes, reads, traps);
          for (i = 0; i < 7; i = i + 1)
            if (retire_counts[i] != 1) $fatal(1, "M stream instruction lost or retired twice pc=%08x count=%0d", 32'h40 + 4*i, retire_counts[i]);
          cases = cases + 1;
        end
    $display("M IRQ style=%0d PASS: %0d cases", PC_STYLE, cases);
    done = 1;
  end
endmodule
module tb_rv32m_wait_irq;
  wire done0, done1;
  rv32m_wait_irq_runner #(.PC_STYLE(0)) style0(done0);
  rv32m_wait_irq_runner #(.PC_STYLE(1)) style1(done1);
  initial begin
    wait(done0 && done1);
    $display("RV32M WAIT IRQ PASS: 648 cases");
    $finish;
  end
endmodule
`default_nettype wire
