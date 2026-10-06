`timescale 1ns/1ps
`default_nettype none
module tb_ptrocos_app_memory;
  reg clk=0,rst=1,valid=0,we=0;
  reg [31:0] addr=0,wdata=0,instruction_addr=0;
  reg [3:0] wstrb=0;
  wire ready,error;wire [31:0] rdata,instruction_data;
  ptrocos_app_memory dut(.*);
  always #5 clk=~clk;
  reg [31:0] expected[0:4095];
  integer transactions=0,fetches=0,cycles=0,commits=0;
  reg initialized=0;
  always @(posedge clk) if(!rst) begin
    cycles++;if(cycles>300000) $fatal(1,"App memory timeout");
    if(valid && ready) transactions++;
  end
  always @(negedge clk) if(!rst) begin
    if(dut.target_valid && !dut.seen && dut.selected && dut.target_we) commits++;
    #1;
    if(initialized && instruction_addr[31:14]==18'h4 && instruction_addr[1:0]==0) begin
      if(instruction_data!==expected[instruction_addr[13:2]]) $fatal(1,"App instruction word %x",instruction_addr);
      fetches++;
    end else if(instruction_addr[31:14]!=18'h4 || instruction_addr[1:0]!=0)
      if(instruction_data!==0) $fatal(1,"App instruction high address alias");
  end
  task transaction(input bit writing,input [31:0] address,data,input [3:0] strobes,input bit fault);
    integer before_commits;
    @(negedge clk);#2;before_commits=commits;valid=1;we=writing;addr=address;wdata=data;wstrb=strobes;
    do @(posedge clk);while(!ready);
    if(error!==fault) $fatal(1,"App error response %x",address);
    if(!fault && !writing && rdata!==expected[address[13:2]]) $fatal(1,"App data read %x got %x",address,rdata);
    if(fault && rdata!==0) $fatal(1,"App rejected read leaked data");
    if(commits-before_commits!=(writing && !fault)) $fatal(1,"App duplicated/missing store");
    // Read-first BRAM permits same-edge old instruction data. Keep fetch idle
    // while updating the reference, then verify newly published data later.
    if(writing && !fault) for(integer lane=0;lane<4;lane++) if(strobes[lane])
      expected[address[13:2]][lane*8+:8]=data[lane*8+:8];
    #1;valid=0;we=0;repeat(2) @(posedge clk);
  endtask
  reg [31:0] random_state=32'h454c4631;
  function automatic [31:0] step(input [31:0] state);
    reg [31:0] x;x=state^(state<<13);x=x^(x>>17);return x^(x<<5);
  endfunction
  initial begin
    repeat(5) @(posedge clk);#1;rst=0;
    for(integer i=0;i<4096;i++) begin
      expected[i]=0;transaction(1,32'h10000+i*4,(i*32'h9e3779b9)^32'ha55a1357,15,0);
    end
    initialized=1;
    for(integer i=0;i<4096;i++) begin
      @(posedge clk);#1;instruction_addr=32'h10000+i*4;
      transaction(0,32'h10000+i*4,0,0,0);
    end
    instruction_addr=0;
    for(integer i=0;i<512;i++) begin
      random_state=step(random_state);
      transaction(1,32'h10000+{18'd0,random_state[11:0],2'b0},random_state,random_state[19:16],0);
      transaction(0,32'h10000+{18'd0,random_state[11:0],2'b0},0,0,0);
    end
    foreach(expected[i]) begin @(posedge clk);#1;instruction_addr=32'h10000+i*4;@(negedge clk);#2;end
    @(posedge clk);#1;instruction_addr=32'h10010000;
    transaction(1,32'h10010000,32'hdeadbeef,15,1);
    transaction(0,32'h00014000,0,0,1);
    transaction(0,32'h0000fffc,0,0,1);
    transaction(0,32'h80010000,0,0,1);
    @(posedge clk);#1;instruction_addr=32'h10002;repeat(3) @(posedge clk);
    #1;rst=1;repeat(3) @(posedge clk);#1;rst=0;instruction_addr=32'h10000;
    transaction(0,32'h10000,0,0,0);
    if(transactions!=9221 || commits!=4608 || fetches<8192) $fatal(1,"App coverage transactions=%0d commits=%0d fetches=%0d",transactions,commits,fetches);
    $display("PTROCOS APP MEMORY UNIT PASS transactions=%0d stores=%0d fetches=%0d cycles=%0d full-address byte-lanes read-first no-duplicate reset",transactions,commits,fetches,cycles);
    $finish;
  end
endmodule
`default_nettype wire
