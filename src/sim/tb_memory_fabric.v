`default_nettype none
module cdc_memory_runner(output reg done=0);
  reg sc=0, tc=0, rst=1, sv=0, sw=0;
  reg [31:0] sa=0, sd=0;
  reg [3:0] ss=0;
  wire sr, se, tv, tw;
  wire [31:0] rd, ta, td;
  wire [3:0] ts;
  integer delay=0, requests=0, i, timeout;
  reg [31:0] pending_addr, pending_data;
  reg pending_we;
  reg [3:0] pending_strobes;
  wire tr=delay==1;
  word_bus_cdc dut(.source_clk(sc),.source_rst(rst),.source_valid(sv),.source_we(sw),
      .source_addr(sa),.source_wdata(sd),.source_wstrb(ss),.source_ready(sr),
      .source_rdata(rd),.source_error(se),.target_clk(tc),.target_rst(rst),
      .target_valid(tv),.target_we(tw),.target_addr(ta),.target_wdata(td),.target_wstrb(ts),
      .target_ready(tr),.target_rdata(ta^td),.target_error(ta[6]));
  always #5 sc=~sc;
  always #6.5 tc=~tc;
  always @(posedge tc or posedge rst) begin
    if(rst) begin delay<=0; requests=0; end
    else begin
      if(tv && delay==0) begin
        delay<=6; requests=requests+1;
        pending_addr<=ta; pending_data<=td; pending_we<=tw; pending_strobes<=ts;
      end else if(delay>1) delay<=delay-1;
      else if(tr) delay<=0;
      if(delay!=0 && (!tv || ta!==pending_addr || td!==pending_data || tw!==pending_we || ts!==pending_strobes))
        $fatal(1,"CDC target payload changed before completion");
    end
  end
  initial begin
    repeat(4) @(negedge sc); rst=0;
    // 只有同时复位两个时钟域，才能取消邮箱中的事务。
    sv=1; sa=32'h80000000; sd=123;
    wait(tv); @(negedge sc); rst=1; sv=0;
    repeat(4) @(negedge sc); rst=0;
    repeat(15) @(negedge sc);
    if(tv || sr || requests!=0) $fatal(1,"CDC produced a ghost request after reset");
    for(i=0;i<64;i=i+1) begin
      @(negedge sc); sv=1; sa=32'h80000000+4*i; sd=32'habc00000+i; ss=i; sw=i%2;
      timeout=0;
      while(!sr && timeout<60) begin @(negedge sc); timeout=timeout+1; end
      if(!sr || rd!==(sa^sd) || se!==sa[6]) $fatal(1,"CDC lost payload or response");
      @(negedge sc); sv=0;
      repeat(2) @(negedge sc);
    end
    if(requests!=64) $fatal(1,"CDC duplicated requests: %0d",requests);
    $display("WORD CDC PASS: 64 asynchronous requests and joint reset cancellation");
    done=1;
  end
endmodule

module arbiter_memory_runner(output reg done=0);
  reg clk=0,rst=1;
  integer cpu_count=0,dma_count=0,grants=0,delay=0,cycles=0;
  wire cv=cpu_count<20, dv=dma_count<20;
  wire cr,dr,ce,de,v,we;
  wire [31:0] ca=32'h80000000+cpu_count*4, da=32'h80000100+dma_count*4;
  wire [31:0] cd,dd,a,d;
  wire [3:0] st;
  reg [31:0] pending_addr,pending_data;
  reg [3:0] pending_strobes;
  reg pending_we,last_owner=1;
  wire ready=delay==1;
  word_bus_arbiter dut(.clk(clk),.rst(rst),.cpu_valid(cv),.cpu_we(1'b0),
      .cpu_addr(ca),.cpu_wdata(32'd0),.cpu_wstrb(4'd0),.cpu_ready(cr),.cpu_rdata(cd),.cpu_error(ce),
      .dma_valid(dv),.dma_we(1'b0),.dma_addr(da),.dma_wdata(32'd0),.dma_wstrb(4'd0),
      .dma_ready(dr),.dma_rdata(dd),.dma_error(de),.valid(v),.we(we),.addr(a),.wdata(d),
      .wstrb(st),.ready(ready),.rdata(pending_addr^32'hbeef),.error(pending_addr[4]));
  always #5 clk=~clk;
  always @(posedge clk) if(!rst && !done) begin
    cycles<=cycles+1;
    if(cycles>600) $fatal(1,"arbiter starvation timeout");
    if(v && delay==0) begin
      if(cv && dv && a[8]==last_owner) $fatal(1,"arbiter did not alternate pending masters");
      last_owner<=a[8]; delay<=3+grants%5; grants<=grants+1;
      pending_addr<=a; pending_data<=d; pending_strobes<=st; pending_we<=we;
    end else if(delay>1) delay<=delay-1;
    else if(ready) delay<=0;
    if(delay!=0 && (!v || a!==pending_addr || d!==pending_data || st!==pending_strobes || we!==pending_we))
      $fatal(1,"arbiter changed a live grant");
    if(cr && dr) $fatal(1,"arbiter completed both masters");
    if(cr) begin
      if(cd!==(ca^32'hbeef) || ce!==ca[4]) $fatal(1,"CPU received another master's response");
      cpu_count<=cpu_count+1;
    end
    if(dr) begin
      if(dd!==(da^32'hbeef) || de!==da[4]) $fatal(1,"DMA received another master's response");
      dma_count<=dma_count+1;
    end
  end
  initial begin
    repeat(4) @(negedge clk); rst=0;
    wait(cpu_count==20 && dma_count==20);
    repeat(3) @(negedge clk);
    if(grants!=40 || v) $fatal(1,"arbiter duplicated transactions");
    $display("WORD ARBITER PASS: 40 contended requests, fairness and response ownership");
    done=1;
  end
endmodule

module dma_memory_runner(output reg done=0);
  reg clk=0,rst=1,mv=0,mw=0;
  reg [31:0] ma=0,md=0;
  reg [3:0] ms=0;
  wire [31:0] mr,a,d;
  wire v,we;
  wire [3:0] st;
  reg [31:0] memory[0:511];
  integer delay=0,requests=0,writes=0,i,timeout,before_requests,before_writes;
  reg [31:0] pending_addr,pending_data,status,completed;
  reg pending_we;
  reg inject_error=0;
  reg [31:0] error_addr=0;
  wire ready=delay==1;
  wire error=inject_error && pending_addr==error_addr;
  dma_copy dut(.clk(clk),.rst(rst),.mmio_valid(mv),.mmio_we(mw),.mmio_addr(ma),
      .mmio_wdata(md),.mmio_wstrb(ms),.mmio_rdata(mr),.mem_valid(v),.mem_we(we),
      .mem_addr(a),.mem_wdata(d),.mem_wstrb(st),.mem_ready(ready),
      .mem_rdata(memory[pending_addr[10:2]]),.mem_error(error));
  always #5 clk=~clk;
  always @(posedge clk) if(!rst) begin
    if(v && delay==0) begin
      delay<=7; pending_addr<=a; pending_data<=d; pending_we<=we;
      requests=requests+1;
    end else if(delay>1) delay<=delay-1;
    else if(ready) delay<=0;
    if(delay!=0 && (!v || a!==pending_addr || d!==pending_data || we!==pending_we))
      $fatal(1,"DMA abandoned a pending bus request");
    if(v && ready && we && !error) begin
      if(st!=15) $fatal(1,"DMA wrote a partial word");
      memory[pending_addr[10:2]]<=pending_data; writes=writes+1;
    end
  end
  task write_reg;
    input [5:0] offset;
    input [31:0] value;
    begin
      @(negedge clk); mv=1;mw=1;ma=32'h4000a000+offset;md=value;ms=15;
      @(negedge clk); mv=0;
    end
  endtask
  task read_reg;
    input [5:0] offset;
    output [31:0] value;
    begin
      @(negedge clk); mv=1;mw=0;ma=32'h4000a000+offset;
      @(negedge clk); value=mr;mv=0;
    end
  endtask
  task configure;
    input [31:0] source,destination,count;
    begin write_reg(0,source);write_reg(4,destination);write_reg(8,count); end
  endtask
  task finish_job;
    input [7:0] code;
    input [31:0] count;
    begin
      timeout=0;
      while(v && timeout<600) begin @(negedge clk);timeout=timeout+1;end
      read_reg(16,status);read_reg(20,completed);
      if(timeout==600 || status[0] || !status[1] || status[2]!=(code!=0) || status[15:8]!=code || completed!=count)
        $fatal(1,"DMA status mismatch status=%08x count=%0d expected=%0d/%0d",status,completed,code,count);
    end
  endtask
  initial begin
    for(i=0;i<512;i=i+1) memory[i]=32'h12340000+i;
    repeat(4) @(negedge clk);rst=0;
    configure(32'h80000000,32'h80000100,8);write_reg(12,1);
    // 重新配置和重复启动不得替换正在执行的任务。
    configure(32'h80000200,32'h80000300,2);write_reg(12,1);
    finish_job(0,8);
    for(i=0;i<8;i=i+1) if(memory[64+i]!==memory[i]) $fatal(1,"DMA copied wrong data");
    before_requests=requests;
    configure(32'h80000001,32'h80000100,1);write_reg(12,1);finish_job(1,0);
    configure(32'h80000000,32'h88000000,1);write_reg(12,1);finish_job(2,0);
    configure(32'h87fffffc,32'h80000100,2);write_reg(12,1);finish_job(2,0);
    configure(32'h80000000,32'h80000100,32'hffffffff);write_reg(12,1);finish_job(2,0);
    configure(32'h80000000,32'h80000004,8);write_reg(12,1);finish_job(3,0);
    configure(0,0,0);write_reg(12,1);finish_job(0,0);
    if(requests!=before_requests) $fatal(1,"invalid/empty DMA issued memory requests");
    before_writes=writes;
    configure(32'h80000000,32'h80000100,8);write_reg(12,1);write_reg(12,2);finish_job(5,0);
    if(writes!=before_writes) $fatal(1,"read-phase abort wrote memory");
    configure(32'h80000000,32'h80000100,8);write_reg(12,1);
    wait(v && we && delay>3);write_reg(12,2);finish_job(5,1);
    if(writes!=before_writes+1) $fatal(1,"write-phase abort did not drain exactly one write");
    inject_error=1;error_addr=32'h80000010;
    configure(32'h80000010,32'h80000100,4);write_reg(12,1);finish_job(4,0);
    inject_error=0;
    configure(32'h80000000,32'h80000200,4);write_reg(12,1);finish_job(0,4);
    for(i=0;i<4;i=i+1) if(memory[128+i]!==memory[i]) $fatal(1,"DMA did not recover after error");
    write_reg(12,4);read_reg(16,status);
    if(status!=0) $fatal(1,"DMA sticky flags did not clear");
    $display("DMA COPY PASS: copy, frozen config, bounds/overflow/overlap, zero count, read/write abort, bus error and recovery");
    done=1;
  end
endmodule

module tb_memory_fabric;
  wire a,b,c;
  cdc_memory_runner cdc(a);
  arbiter_memory_runner arbiter(b);
  dma_memory_runner dma(c);
  initial begin
    wait(a && b && c);
    $display("MEMORY FABRIC PASS");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1,"memory fabric global timeout");
  end
endmodule
`default_nettype wire
