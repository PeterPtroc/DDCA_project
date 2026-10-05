`timescale 1ns/1ps
`default_nettype none
// Physical pin simulation using the generated MIG simulation RTL and its DDR2
// model. FAST calibration is a simulation convenience, not board validation.
module tb_ptrocos_mig;
  reg clk=0,reset_n=0;
  wire [12:0] addr;
  wire [2:0] ba;
  wire ras_n,cas_n,we_n,ck_p,ck_n,cke,cs_n,odt,uart_tx;
  wire [1:0] dm,dqs_p,dqs_n;
  wire [15:0] dq;
  integer cycles=0,timer_irqs=0,load_faults=0,store_faults=0,bit_index;
  reg [7:0] received;
  string line="";
  integer passes=0,crc_lines=0;
  ptrocos_nexys_a7_top #(.UART_DIVIDER(16)) dut (
      .clk100(clk),.reset_n(reset_n),.sw(16'd0),.btn(5'd0),.uart_rx(1'b1),.jb1(1'b0),
      .ps2_clk(1'b1),.ps2_data(1'b1),
      .led(),.uart_tx(uart_tx),.pmod_ja(),.seg_an(),.seg(),.seg_dp(),
      .rgb0_r(),.rgb0_g(),.rgb0_b(),.rgb1_r(),.rgb1_g(),.rgb1_b(),
      .ddr2_addr(addr),.ddr2_ba(ba),.ddr2_ras_n(ras_n),.ddr2_cas_n(cas_n),.ddr2_we_n(we_n),
      .ddr2_ck_p(ck_p),.ddr2_ck_n(ck_n),.ddr2_cke(cke),.ddr2_cs_n(cs_n),.ddr2_odt(odt),
      .ddr2_dm(dm),.ddr2_dq(dq),.ddr2_dqs_p(dqs_p),.ddr2_dqs_n(dqs_n)
  );
  // 1024 fully tagged bursts cover this diagnostic and calibration traffic.
  // The vendor default scans 32768 entries per access, making XSim much slower.
  ddr2_model #(.MEM_BITS(10),.DEBUG(0)) dram (
      .ck(ck_p),.ck_n(ck_n),.cke(cke),.cs_n(cs_n),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),
      .dm_rdqs(dm),.ba(ba),.addr(addr),.dq(dq),.dqs(dqs_p),.dqs_n(dqs_n),.rdqs_n(),.odt(odt)
  );
  always #5 clk=~clk;
  always @(posedge dut.cpu_clk) begin
    cycles<=cycles+1;
    if(cycles%50000==0) $display("MIG PROGRESS cycles=%0d calibrated=%b pc=%08x",cycles,dut.calibrated,dut.soc.ia);
    if(cycles>800000) $fatal(1,"MIG firmware timeout calib=%b locked=%b pc=%08x",dut.calibrated,dut.mig_locked,dut.soc.ia);
    if(!dut.calibrated && !dut.cpu_rst) $fatal(1,"CPU released before calibration");
    if(dut.soc.firmware_result[31:20]==12'hbad) $fatal(1,"MIG firmware failure %08x",dut.soc.firmware_result);
    if(!dut.cpu_rst && dut.soc.trap_taken) begin
      case(dut.soc.trap_cause)
        5:load_faults<=load_faults+1;
        7:store_faults<=store_faults+1;
        32'h80000007:timer_irqs<=timer_irqs+1;
        default:$fatal(1,"MIG unexpected trap %08x",dut.soc.trap_cause);
      endcase
    end
  end
  initial forever begin
    @(negedge uart_tx);
    if(!dut.cpu_rst) begin
      repeat(24) @(posedge dut.cpu_clk);
      for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
        received[bit_index]=uart_tx;repeat(16) @(posedge dut.cpu_clk);
      end
      if(uart_tx!==1) $fatal(1,"MIG UART framing error");
      $write("%c",received);
      if(received==10) begin
        if(line=="DDR2 DMA PASS") passes=passes+1;
        if(line=="DMA CRC 0000f364") crc_lines=crc_lines+1;
        line="";
      end else line={line,received};
    end
  end
  initial begin
    #8000000 $fatal(1,"MIG global timeout: clocks/calibration failed");
  end
  initial begin
    #200 reset_n=1;
    wait(dut.calibrated===1);$display("MIG SIMULATION CALIBRATED at %0t",$time);
`ifdef PTROCOS_MIG_FULL_DIAGNOSTIC
    wait(dut.soc.firmware_result==32'h600d600d && passes==1);
    if(crc_lines!=1 || load_faults!=1 || store_faults!=1 || timer_irqs<2)
      $fatal(1,"MIG acceptance coverage CRC=%0d load=%0d store=%0d timer=%0d",crc_lines,load_faults,store_faults,timer_irqs);
    $display("PTROCOS MIG PIN SIM PASS cycles=%0d timer=%0d CRC=f364",cycles,timer_irqs);
`else
    // The diagnostic reaches the deliberate faults only after it has verified
    // all DDR address bits, the last word, and byte/halfword access semantics.
    // Full software/DMA acceptance runs in the sparse SoC test and on hardware.
    wait(load_faults==1 && store_faults==1);
    repeat(10) @(posedge dut.cpu_clk);
    if(dut.soc.firmware_result[31:20]==12'hbad) $fatal(1,"MIG smoke firmware failure");
    $display("PTROCOS MIG LINK SMOKE PASS cycles=%0d: calibration, address lines, byte lanes, access faults",cycles);
`endif
    $finish;
  end
endmodule
`default_nettype wire
