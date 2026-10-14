`timescale 1ns/1ps
`default_nettype none
// Real RV32IM datapath: MEM is implemented as two registered substages.
module tb_pipeline_demo;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [31:0] rom [0:63];
  reg [31:0] ram [0:15];
  wire [31:0] ia, da, wd;
  wire dv, we;
  wire [3:0] strb;
  reg [31:0] rd = 0;
  wire retired, rd_we, stalled, flushed, trap;
  wire [31:0] rpc, rinsn, result;
  wire [4:0] dest;
  integer cycle = 0, stalls = 0, flushes = 0, commits = 0, forwards = 0;
  integer i, b, csv;
  reg done = 0;
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
    .event_branch(), .event_branch_taken(), .event_custom_crc()
  );
  // Fixed-width ASCII labels are readable with XSim's ASCII radix.
  function [8*28-1:0] label;
    input valid;
    input [31:0] pc;
    begin
      if (!valid) label = "--- BUBBLE ---";
      else case (pc)
        0: label = "I00 addi x1,x0,5";
        4: label = "I01 addi x2,x0,7";
        8: label = "I02 add x3,x1,x2";
        12: label = "I03 add x4,x3,x1";
        16: label = "I04 sw x4,0(x0)";
        20: label = "I05 lw x5,0(x0)";
        24: label = "I06 add x6,x5,x1";
        28: label = "I07 beq x6,x6,+12";
        32: label = "WRONG addi x10,x0,99";
        36: label = "WRONG sw x1,4(x0)";
        40: label = "I10 addi x7,x6,1";
        44: label = "I11 addi x8,x0,1 DONE";
        default: label = "nop";
      endcase
    end
  endfunction
  wire [223:0] IF_text = label(!rst, ia);
  wire [223:0] ID_text = label(!rst && dut.ifid_valid, dut.ifid_pc);
  wire [223:0] EX_text = label(!rst && dut.idex_valid, dut.idex_pc);
  wire [223:0] MEM1_text = label(!rst && dut.exmem_valid, dut.exmem_pc);
  wire [223:0] MEM2_text = label(!rst && dut.mem2_valid, dut.mem2_pc);
  wire [223:0] WB_text = label(!rst && dut.memwb_valid, dut.memwb_pc);
  initial begin
    for (i=0; i<64; i=i+1) rom[i] = 32'h00000013;
    for (i=0; i<16; i=i+1) ram[i] = 0;
    rom[0]=32'h00500093; rom[1]=32'h00700113;
    rom[2]=32'h002081b3; rom[3]=32'h00118233;
    rom[4]=32'h00402023; rom[5]=32'h00002283;
    rom[6]=32'h00128333; rom[7]=32'h00630663;
    rom[8]=32'h06300513; rom[9]=32'h00102223;
    rom[10]=32'h00130393; rom[11]=32'h00100413;
    csv = $fopen("pipeline_cycles.csv", "w");
    if (!csv) $fatal(1, "Cannot open pipeline_cycles.csv");
    $fdisplay(csv,"cycle,IF,ID,EX,MEM1,MEM2,WB,stall,flush");
    repeat (4) @(negedge clk);
    rst = 0;
  end
  // Sample before the edge updates: each row describes the instructions
  // occupying stages and control decisions consumed at this rising edge.
  always @(posedge clk) if (!rst && !done) begin
    cycle = cycle + 1;
    $fdisplay(csv,"%0d,\"%0s\",\"%0s\",\"%0s\",\"%0s\",\"%0s\",\"%0s\",%0b,%0b",
      cycle, IF_text, ID_text, EX_text, MEM1_text, MEM2_text, WB_text, stalled, flushed);
    if (stalled) stalls = stalls + 1;
    if (flushed) flushes = flushes + 1;
    if (dut.idex_valid && (dut.fwd_a != 0 || dut.fwd_b != 0)) forwards = forwards + 1;
    if (trap) $fatal(1,"Unexpected trap");
    if (cycle > 80) $fatal(1,"Pipeline timeout");
    if (dv) begin
      if (da >= 64 || da[1:0] != 0) $fatal(1,"Unexpected memory address");
      if (we) begin
        for (b=0; b<4; b=b+1)
          if (strb[b]) ram[da[5:2]][b*8 +: 8] <= wd[b*8 +: 8];
      end else rd <= ram[da[5:2]];
    end
    if (retired) begin
      commits = commits + 1;
      if (rpc == 32 || rpc == 36) $fatal(1,"Wrong-path instruction retired");
      case (rpc)
        0: if (!rd_we || dest != 1 || result !== 5) $fatal(1,"x1 mismatch");
        4: if (!rd_we || dest != 2 || result !== 7) $fatal(1,"x2 mismatch");
        8: if (!rd_we || dest != 3 || result !== 12) $fatal(1,"forward x3 mismatch");
        12: if (!rd_we || dest != 4 || result !== 17) $fatal(1,"forward x4 mismatch");
        20: if (!rd_we || dest != 5 || result !== 17) $fatal(1,"load mismatch");
        24: if (!rd_we || dest != 6 || result !== 22) $fatal(1,"load-use mismatch");
        40: if (!rd_we || dest != 7 || result !== 23) $fatal(1,"target mismatch");
        44: begin
          if (!rd_we || dest != 8 || result !== 1 || commits != 10 ||
              stalls != 2 || flushes != 1 || forwards == 0 ||
              ram[0] !== 17 || ram[1] !== 0 || dut.rf.regs[10] !== 0)
            $fatal(1,"Final state/coverage mismatch");
          done = 1;
          $fclose(csv);
          $display("PIPELINE DEMO PASS: cycles=%0d commits=%0d stalls=%0d flushes=%0d",cycle,commits,stalls,flushes);
          #1; $finish;
        end
        default: ;
      endcase
    end
  end
endmodule
`default_nettype wire
