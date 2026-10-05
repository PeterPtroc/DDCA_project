`default_nettype none
module memory_fault_runner #(parameter PC_STYLE = 0) (output reg done=0);
  reg clk=0, rst=1;
  reg [31:0] rom[0:127];
  wire [31:0] ia, da, dw, cause, retire_pc;
  wire dv, we, trap, retired;
  reg [31:0] dr=0;
  reg [3:0] delay=0;
  wire ready=delay==1;
  wire error=da==32'h80000000 || da==32'h80000004;
  integer i, requests=0, traps=0, writes=0, cycles=0;
  reg [31:0] pending_addr, pending_data;
  reg pending_we;
  rv32im_mem_core #(.CPU_PC_NEXT_STYLE(PC_STYLE)) dut (
      .clk(clk), .rst(rst), .imem_addr(ia), .imem_rdata(rom[ia[8:2]]),
      .dmem_valid(dv), .dmem_we(we), .dmem_wstrb(), .dmem_addr(da),
      .dmem_wdata(dw), .dmem_rdata(dr), .dmem_ready(ready), .dmem_error(error),
      .machine_timer_irq(1'b0), .machine_software_irq(1'b0),
      .retire_valid(retired), .retire_pc(retire_pc), .retire_insn(),
      .retire_rd_we(), .retire_rd(), .retire_rd_data(), .trap_taken(trap),
      .trap_cause(cause), .event_stall_load(), .event_fwd_ex_count(),
      .event_fwd_wb_count(), .event_flush(), .event_branch(),
      .event_branch_taken(), .event_custom_crc()
  );
  always #5 clk=~clk;
  always @(posedge clk) if (!rst) begin
    cycles=cycles+1;
    if(cycles>400) $fatal(1,"memory fault timeout");
    if(dv && delay==0) begin
      delay<=5; pending_addr<=da; pending_data<=dw; pending_we<=we;
    end else if(delay>1) delay<=delay-1;
    else if(ready) delay<=0;
    if(delay!=0 && (!dv || da!==pending_addr || dw!==pending_data || we!==pending_we))
      $fatal(1,"memory fault cancelled a live request");
    if(dv && ready) begin
      requests=requests+1;
      if(!we) dr<=32'h55;
      else if(!error) begin
        writes=writes+1;
        if(da!=32'h8000000c || dw!=32'h55) $fatal(1,"wrong store after access faults");
      end
    end
    if(retired && (retire_pc==32'h40 || retire_pc==32'h44)) $fatal(1,"faulting memory instruction retired");
    if(trap) begin
      if(cause!=(traps==0 ? 5 : 7) || dut.memwb_exc_tval!=(traps==0 ? 32'h80000000 : 32'h80000004))
        $fatal(1,"wrong access-fault cause or mtval");
      traps=traps+1;
    end
  end
  initial begin
    for(i=0;i<128;i=i+1) rom[i]=32'h00000013;
    rom[0]=32'h10000393;
    rom[1]=32'h30539073; // mtvec
    rom[2]=32'h800002b7; // t0=DDR
    rom[3]=32'h05500313;
    rom[16]=32'h0002a483; // failed lw s1,0(t0)
    rom[17]=32'h0062a223; // failed sw t1,4(t0)
    rom[18]=32'h0082a903; // successful lw s2,8(t0)
    rom[19]=32'h0122a623; // successful sw s2,12(t0)
    rom[20]=32'h0000006f;
    rom[64]=32'h341023f3;
    rom[65]=32'h00438393;
    rom[66]=32'h34139073;
    rom[67]=32'h30200073;
    repeat(6) @(negedge clk); rst=0;
    repeat(250) @(negedge clk);
    if(requests!=4 || traps!=2 || writes!=1 || dut.rf.regs[9]!=0 || dut.rf.regs[18]!=32'h55)
      $fatal(1,"access fault did not recover precisely requests=%0d traps=%0d writes=%0d",requests,traps,writes);
    done=1;
  end
endmodule
module tb_memory_faults;
  wire done0, done1;
  memory_fault_runner #(.PC_STYLE(0)) style0(done0);
  memory_fault_runner #(.PC_STYLE(1)) style1(done1);
  initial begin
    wait(done0 && done1);
    $display("MEMORY FAULT PASS: delayed load/store access faults and recovery in both PC styles");
    $finish;
  end
endmodule
`default_nettype wire
