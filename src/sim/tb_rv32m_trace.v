`default_nettype none

module tb_rv32m_trace #(parameter PC_STYLE = 0);
  localparam [31:0] DATA_BASE = 32'h10000000;
  localparam [31:0] TEST_RESULT = 32'h4000000c;
  localparam [31:0] PASS_VALUE = 32'h600d600d;

  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [31:0] imem[0:16383];
  reg [31:0] dmem[0:1023];
  reg [8*512-1:0] hex_path;
  reg [8*512-1:0] trace_path;
  reg [8*512-1:0] metrics_path;
  integer trace_fd;
  integer metrics_fd;
  integer i;
  integer cycles = 0;
  integer retire_step = 0;
  integer stall_count = 0;
  integer flush_count = 0;

  wire [31:0] imem_addr;
  wire [31:0] imem_rdata = imem[imem_addr[15:2]];
  wire dmem_valid;
  wire dmem_we;
  wire [3:0] dmem_wstrb;
  wire [31:0] dmem_addr;
  wire [31:0] dmem_wdata;
  reg [31:0] dmem_rdata = 32'd0;
  wire retire_valid;
  wire [31:0] retire_pc;
  wire [31:0] retire_insn;
  wire retire_rd_we;
  wire [4:0] retire_rd;
  wire [31:0] retire_rd_data;
  wire event_stall_load;
  wire [1:0] event_fwd_ex_count;
  wire [1:0] event_fwd_wb_count;
  wire event_flush;
  wire event_branch;
  wire event_branch_taken;
  wire event_custom_crc;

  reg previous_mem_we = 1'b0, previous2_mem_we = 1'b0;
  reg [31:0] previous_mem_addr = 32'd0, previous2_mem_addr = 32'd0;
  reg [31:0] previous_mem_data = 32'd0, previous2_mem_data = 32'd0;

  wire trap_taken;
  rv32im_core #(.CPU_PC_NEXT_STYLE(PC_STYLE)) dut (
      .clk(clk),
      .rst(rst),
      .imem_addr(imem_addr),
      .imem_rdata(imem_rdata),
      .dmem_valid(dmem_valid),
      .dmem_we(dmem_we),
      .dmem_wstrb(dmem_wstrb),
      .dmem_addr(dmem_addr),
      .dmem_wdata(dmem_wdata),
      .dmem_rdata(dmem_rdata),
      .machine_timer_irq(1'b0),
      .machine_software_irq(1'b0),
      .retire_valid(retire_valid),
      .retire_pc(retire_pc),
      .retire_insn(retire_insn),
      .retire_rd_we(retire_rd_we),
      .retire_rd(retire_rd),
      .retire_rd_data(retire_rd_data),
      .trap_taken(trap_taken),
      .trap_cause(),
      .event_stall_load(event_stall_load),
      .event_fwd_ex_count(event_fwd_ex_count),
      .event_fwd_wb_count(event_fwd_wb_count),
      .event_flush(event_flush),
      .event_branch(event_branch),
      .event_branch_taken(event_branch_taken),
      .event_custom_crc(event_custom_crc)
  );

  always #5 clk = ~clk;

  initial begin
    if ($test$plusargs("RV32M_TEST")) begin
      hex_path = "build/rv32m/isa.hex";
      trace_path = PC_STYLE == 0 ? "build/rv32m/isa.rtl.csv" : "build/rv32m/isa.alt.rtl.csv";
      metrics_path = PC_STYLE == 0 ? "build/rv32m/metrics.csv" : "build/rv32m/metrics.alt.csv";
    end else if ($test$plusargs("ISA_TEST")) begin
      hex_path = "build/hex/isa_test.hex";
      trace_path = "build/trace/isa_test.rtl.csv";
      metrics_path = "build/benchmark/isa_test.csv";
    end else if ($test$plusargs("HAZARD_TEST")) begin
      hex_path = "build/hex/hazard_test.hex";
      trace_path = "build/trace/hazard_test.rtl.csv";
      metrics_path = "build/benchmark/hazard_test.csv";
    end else if ($test$plusargs("CRC_TEST")) begin
      hex_path = "build/hex/crc_test.hex";
      trace_path = "build/trace/crc_test.rtl.csv";
      metrics_path = "build/benchmark/crc_test.csv";
    end else begin
      $fatal(1, "select +RV32M_TEST, +ISA_TEST, +HAZARD_TEST, or +CRC_TEST");
    end
    for (i = 0; i < 16384; i = i + 1) imem[i] = 32'h00000013;
    for (i = 0; i < 1024; i = i + 1) dmem[i] = 32'd0;
    $readmemh(hex_path, imem);
    trace_fd = $fopen(trace_path, "w");
    if (trace_fd == 0) $fatal(1, "cannot open trace output");
    metrics_fd = $fopen(metrics_path, "w");
    if (metrics_fd == 0) $fatal(1, "cannot open benchmark output");
    $fdisplay(trace_fd, "step,pc,insn,rd_we,rd,rd_data,mem_we,mem_addr,mem_data");
    $fdisplay(metrics_fd, "cycles,instret,stall,flush");
    repeat (10) @(negedge clk);
    rst = 1'b0;
  end

  always @(posedge clk) begin
    if (rst) begin
      previous_mem_we <= 1'b0;
      previous2_mem_we <= 1'b0;
      previous_mem_addr <= 32'd0;
      previous2_mem_addr <= 32'd0;
      previous_mem_data <= 32'd0;
      previous2_mem_data <= 32'd0;
      dmem_rdata <= 32'd0;
      cycles <= 0;
      retire_step <= 0;
      stall_count <= 0;
      flush_count <= 0;
    end else begin
      cycles <= cycles + 1;
      if (event_stall_load) stall_count <= stall_count + 1;
      if (event_flush) flush_count <= flush_count + 1;
      if (trap_taken) $fatal(1, "unexpected trap at pc=%08x", dut.memwb_pc);
      if (cycles > 200000) $fatal(1, "CPU trace timeout after %0d retires", retire_step);

      if (retire_valid) begin
        if ((retire_insn[6:0] == 7'b0100011) != previous2_mem_we)
          $fatal(1, "store/retire alignment mismatch at pc=%08x", retire_pc);
        $fdisplay(
            trace_fd,
            "%0d,%08x,%08x,%0d,%0d,%08x,%0d,%08x,%08x",
            retire_step,
            retire_pc,
            retire_insn,
            retire_rd_we && (retire_rd != 0),
            (retire_rd_we && (retire_rd != 0)) ? retire_rd : 0,
            (retire_rd_we && (retire_rd != 0)) ? retire_rd_data : 0,
            previous2_mem_we,
            previous2_mem_we ? previous2_mem_addr : 0,
            previous2_mem_we ? previous2_mem_data : 0
        );
        retire_step <= retire_step + 1;

        if (previous2_mem_we && previous2_mem_addr == TEST_RESULT) begin
          $fclose(trace_fd);
          if (previous2_mem_data != PASS_VALUE)
            $fatal(1, "firmware FAIL result=%08x", previous2_mem_data);
          $fdisplay(metrics_fd, "%0d,%0d,%0d,%0d",
              cycles + 1, retire_step + 1,
              stall_count + (event_stall_load ? 1 : 0),
              flush_count + (event_flush ? 1 : 0));
          $fclose(metrics_fd);
          $display("BENCHMARK: cycles=%0d instret=%0d stall=%0d flush=%0d",
              cycles + 1, retire_step + 1,
              stall_count + (event_stall_load ? 1 : 0),
              flush_count + (event_flush ? 1 : 0));
          $display("RTL TRACE PASS: retires=%0d", retire_step + 1);
          $finish;
        end
      end

      previous2_mem_we <= previous_mem_we;
      previous2_mem_addr <= previous_mem_addr;
      previous2_mem_data <= previous_mem_data;
      previous_mem_we <= dmem_valid && dmem_we;
      previous_mem_addr <= dmem_addr;
      previous_mem_data <= dmem_wdata;
      if (dmem_valid && !dmem_we)
        dmem_rdata <= (dmem_addr[31:12] == DATA_BASE[31:12]) ?
                      dmem[dmem_addr[11:2]] : 32'd0;
      if (dmem_valid && dmem_we && dmem_addr[31:12] == DATA_BASE[31:12]) begin
        if (dmem_wstrb[0]) dmem[dmem_addr[11:2]][7:0] <= dmem_wdata[7:0];
        if (dmem_wstrb[1]) dmem[dmem_addr[11:2]][15:8] <= dmem_wdata[15:8];
        if (dmem_wstrb[2]) dmem[dmem_addr[11:2]][23:16] <= dmem_wdata[23:16];
        if (dmem_wstrb[3]) dmem[dmem_addr[11:2]][31:24] <= dmem_wdata[31:24];
      end
    end
  end
endmodule

module tb_rv32m_trace_alt;
  tb_rv32m_trace #(.PC_STYLE(1)) runner();
endmodule

`default_nettype wire
