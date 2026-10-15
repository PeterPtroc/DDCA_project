`timescale 1ns/1ps
`default_nettype none
// 使用实际的 RV32IM 数据通路：MEM 级由两个带寄存器的子级实现。
// 默认循环计算数组之和；CRC_DEMO 模式用相同循环计算数据块的 CRC。
module tb_pipeline_demo;
  reg clk = 0, rst = 1;
  reg [31:0] rom [0:63];
  reg [31:0] ram [0:15];
  wire [31:0] ia, da, wd;
  wire dv, we;
  wire [3:0] strb;
  reg [31:0] rd = 0;
  wire retired, rd_we, stalled, flushed, trap, crc_event;
  wire [31:0] rpc, rinsn, result;
  wire [4:0] dest;
  integer cycle = 0, stalls = 0, flushes = 0, commits = 0, forwards = 0;
  integer i, b, csv, elements, loads = 0, branches = 0, reads = 0, writes = 0, crc_count = 0;
  reg [31:0] expected_result, reference_result, expected_pc = 0;
  reg done = 0;
  // 完成后不再产生周期事件，避免再次 run all 时空跑到无限远。
  initial begin
    while (!done) begin
      #5;
      if (!done) clk = ~clk;
    end
  end
  reg crc_demo, alternate_data;
  rv32im_core dut (
    .clk(clk), .rst(rst), .imem_addr(ia),
    .imem_rdata(ia < 256 ? rom[ia[7:2]] : 32'h00000013),
    .dmem_valid(dv), .dmem_we(we), .dmem_wstrb(strb),
    .dmem_addr(da), .dmem_wdata(wd), .dmem_rdata(rd),
    .machine_timer_irq(1'b0), .machine_software_irq(1'b0),
    .retire_valid(retired), .retire_pc(rpc), .retire_insn(rinsn),
    .retire_rd_we(rd_we), .retire_rd(dest), .retire_rd_data(result),
    .trap_taken(trap), .trap_cause(), .event_stall_load(stalled),
    .event_flush(flushed), .event_fwd_ex_count(), .event_fwd_wb_count(),
    .event_branch(), .event_branch_taken(), .event_custom_crc(crc_event)
  );
  // 定宽 ASCII 标签可在 XSim 中以 ASCII 显示格式查看。
  function [8*40-1:0] label;
    input valid;
    input [31:0] pc;
    begin
      if (!valid) label = "--- BUBBLE ---";
      else case (pc)
        0: label = "I00 BASE addi x1,x0,0";
        4: label = crc_demo ? "I01 COUNT addi x2,x0,9" : "I01 COUNT addi x2,x0,5";
        8: label = crc_demo ? "I02 CRC_INIT addi x3,x0,-1" : "I02 SUM_INIT addi x3,x0,0";
        12: label = "I03 READ lw x4,0(x1)";
        16: label = crc_demo ? "I04 CRC crc16.b x3,x3,x4" : "I04 SUM add x3,x3,x4";
        20: label = "I05 NEXT addi x1,x1,4";
        24: label = "I06 COUNTDOWN addi x2,x2,-1";
        28: label = "I07 LOOP bne x2,x0,-16";
        32: label = crc_demo ? "I08 SAVE sw x3,36(x0)" : "I08 SAVE sw x3,20(x0)";
        36: label = "I09 DONE addi x5,x0,1";
        default: label = "nop";
      endcase
    end
  endfunction
  wire [319:0] IF_text = label(!rst, ia);
  wire [319:0] ID_text = label(!rst && dut.ifid_valid, dut.ifid_pc);
  wire [319:0] EX_text = label(!rst && dut.idex_valid, dut.idex_pc);
  wire [319:0] MEM1_text = label(!rst && dut.exmem_valid, dut.exmem_pc);
  wire [319:0] MEM2_text = label(!rst && dut.mem2_valid, dut.mem2_pc);
  wire [319:0] WB_text = label(!rst && dut.memwb_valid, dut.memwb_pc);
  // 这些别名直接连接实际寄存器和 RAM，便于观察程序的输入与输出。
  wire [31:0] pointer = dut.rf.regs[1], remaining = dut.rf.regs[2];
  wire [31:0] accumulator = dut.rf.regs[3], current_value = dut.rf.regs[4];
  wire [31:0] finished = dut.rf.regs[5], output_value = ram[elements];
  // 测试平台的逐字节参考算法，同时以已知结果 0x4b37 核对完整数据块。
  function [31:0] crc_reference;
    input [31:0] previous;
    input [7:0] value;
    reg [15:0] crc;
    integer bit_index;
    begin
      crc = previous[15:0] ^ {8'd0,value};
      for (bit_index=0; bit_index<8; bit_index=bit_index+1)
        crc = crc[0] ? (crc >> 1) ^ 16'ha001 : crc >> 1;
      crc_reference = {16'd0,crc};
    end
  endfunction
  initial begin
    crc_demo = $test$plusargs("CRC_DEMO");
    alternate_data = $test$plusargs("ALT_DATA");
    elements = crc_demo ? 9 : 5;
    expected_result = crc_demo ? 32'h4b37 : (alternate_data ? 32'd16 : 32'd15);
    reference_result = crc_demo ? 32'hffff : 32'd0;
    for (i=0; i<64; i=i+1) rom[i] = 32'h00000013;
    for (i=0; i<16; i=i+1) ram[i] = 0;
    if (crc_demo) begin
      for (i=0; i<9; i=i+1) ram[i] = 32'h31+i; // 输入字符串“123456789”
    end else if (alternate_data) begin
      ram[0]=10; ram[1]=-4; ram[2]=0; ram[3]=12; ram[4]=-2;
    end else begin
      for (i=0; i<5; i=i+1) ram[i] = i+1;
    end
    rom[0]=32'h00000093; // 数组起始地址：addi x1,x0,0
    rom[1]=crc_demo ? 32'h00900113 : 32'h00500113; // 元素数为九或五
    rom[2]=crc_demo ? 32'hfff00193 : 32'h00000193; // CRC 初值或累加和零
    rom[3]=32'h0000a203; // 读取当前元素：lw x4,0(x1)
    rom[4]=crc_demo ? 32'h0041818b : 32'h004181b3; // 自定义 CRC 更新或加法累加
    rom[5]=32'h00408093; // 指针前进四字节：addi x1,x1,4
    rom[6]=32'hfff10113; // 剩余元素数减一：addi x2,x2,-1
    rom[7]=32'hfe0118e3; // 未结束则回到读取指令：bne x2,x0,-16
    rom[8]=crc_demo ? 32'h02302223 : 32'h00302a23; // 将结果存到输入数据之后
    rom[9]=32'h00100293; // 完成标记：addi x5,x0,1
    csv = $fopen("pipeline_cycles.csv", "w");
    if (!csv) $fatal(1, "Cannot open pipeline_cycles.csv");
    $fdisplay(csv,"cycle,IF,ID,EX,MEM1,MEM2,WB,stall,flush");
    repeat (4) @(negedge clk);
    rst = 0;
  end
  // 在时钟沿触发的状态更新之前采样：每一行记录该上升沿到来时
  // 各流水级中的指令，以及该时钟沿采用的控制决策。
  always @(posedge clk) if (!rst && !done) begin
    cycle = cycle + 1;
    $fdisplay(csv,"%0d,\"%0s\",\"%0s\",\"%0s\",\"%0s\",\"%0s\",\"%0s\",%0b,%0b",
      cycle, IF_text, ID_text, EX_text, MEM1_text, MEM2_text, WB_text, stalled, flushed);
    if (stalled) stalls = stalls + 1;
    if (flushed) flushes = flushes + 1;
    if (crc_event) crc_count = crc_count + 1;
    if (dut.idex_valid && (dut.fwd_a != 0 || dut.fwd_b != 0)) forwards = forwards + 1;
    if (trap) $fatal(1,"Unexpected trap");
    if (cycle > 200) $fatal(1,"Pipeline timeout");
    if (dv) begin
      if (da >= 64 || da[1:0] != 0) $fatal(1,"Unexpected memory address");
      if (we) begin
        if (da !== elements*4 || strb !== 4'b1111 || wd !== expected_result ||
            reads != elements || writes != 0)
          $fatal(1,"Early, repeated or incorrect result store");
        writes = writes + 1;
        for (b=0; b<4; b=b+1)
          if (strb[b]) ram[da[5:2]][b*8 +: 8] <= wd[b*8 +: 8];
      end else begin
        if (reads >= elements || da !== reads*4) $fatal(1,"Input read order mismatch");
        reads = reads + 1;
        rd <= ram[da[5:2]];
      end
    end
    if (retired) begin
      commits = commits + 1;
      if (rpc !== expected_pc) $fatal(1,"Retire order mismatch: expected=%x actual=%x",expected_pc,rpc);
      expected_pc = rpc+4;
      case (rpc)
        0: if (!rd_we || dest != 1 || result !== 0) $fatal(1,"Pointer initialization mismatch");
        4: if (!rd_we || dest != 2 || result !== elements) $fatal(1,"Count initialization mismatch");
        8: if (!rd_we || dest != 3 || result !== (crc_demo ? 32'hffffffff : 32'd0))
          $fatal(1,"Accumulator initialization mismatch");
        12: begin
          if (loads >= elements || !rd_we || dest != 4 || result !== ram[loads])
            $fatal(1,"Loaded element mismatch");
          loads = loads + 1;
        end
        16: begin
          reference_result = crc_demo ? crc_reference(reference_result,ram[loads-1][7:0]) :
            reference_result + ram[loads-1];
          if (!rd_we || dest != 3 || result !== reference_result) $fatal(1,"Accumulation mismatch");
        end
        20: if (!rd_we || dest != 1 || result !== loads*4) $fatal(1,"Pointer update mismatch");
        24: if (!rd_we || dest != 2 || result !== elements-loads) $fatal(1,"Countdown mismatch");
        28: begin
          if (rd_we) $fatal(1,"Branch unexpectedly writes a register");
          branches = branches + 1;
          if (branches < elements) expected_pc = 12;
        end
        32: if (rd_we) $fatal(1,"Store unexpectedly writes a register");
        36: begin
          if (!rd_we || dest != 5 || result !== 1 || commits != 5*elements+5 ||
              stalls != 2*elements || flushes != elements-1 || forwards == 0 ||
              loads != elements || branches != elements || writes != 1 ||
              crc_count != (crc_demo ? elements : 0) ||
              output_value !== expected_result || accumulator !== expected_result ||
              pointer !== elements*4 || remaining !== 0)
            $fatal(1,"Final state/coverage mismatch");
          done = 1;
          $fclose(csv);
          $display("PIPELINE DEMO PASS: cycles=%0d commits=%0d stalls=%0d flushes=%0d",cycle,commits,stalls,flushes);
          $display("FUNCTION DEMO PASS: crc=%0d elements=%0d result=%0d hex=%08x reads=%0d writes=%0d custom_crc=%0d",
            crc_demo,elements,output_value,output_value,reads,writes,crc_count);
          #1; $finish;
        end
        default: ;
      endcase
    end
  end
endmodule
`default_nettype wire
