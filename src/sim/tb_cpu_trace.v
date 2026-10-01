`default_nettype none

module tb_cpu_trace;
  localparam [31:0] DATA_BASE = 32'h10000000;
  localparam [31:0] TEST_RESULT = 32'h4000000c;
  localparam [31:0] PASS_VALUE = 32'h600d600d;

  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [31:0] imem[0:2047];
  reg [31:0] dmem[0:1023];
  reg [8*512-1:0] hex_path;
  reg [8*512-1:0] trace_path;
  integer trace_fd;
  integer i;
  integer cycles = 0;
  integer retire_step = 0;

  wire [31:0] imem_addr;
  wire [31:0] imem_rdata = imem[imem_addr[12:2]];
  wire dmem_valid;
  wire dmem_we;
  wire [31:0] dmem_addr;
  wire [31:0] dmem_wdata;
  wire [31:0] dmem_rdata =
      (dmem_addr[31:12] == DATA_BASE[31:12]) ? dmem[dmem_addr[11:2]] : 32'd0;
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

  reg previous_mem_we = 1'b0;
  reg [31:0] previous_mem_addr = 32'd0;
  reg [31:0] previous_mem_data = 32'd0;

  rv32_core dut (
      .clk(clk),
      .rst(rst),
      .imem_addr(imem_addr),
      .imem_rdata(imem_rdata),
      .dmem_valid(dmem_valid),
      .dmem_we(dmem_we),
      .dmem_addr(dmem_addr),
      .dmem_wdata(dmem_wdata),
      .dmem_rdata(dmem_rdata),
      .retire_valid(retire_valid),
      .retire_pc(retire_pc),
      .retire_insn(retire_insn),
      .retire_rd_we(retire_rd_we),
      .retire_rd(retire_rd),
      .retire_rd_data(retire_rd_data),
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
    if ($test$plusargs("ISA_TEST")) begin
      hex_path = "build/hex/isa_test.hex";
      trace_path = "build/trace/isa_test.rtl.csv";
    end else if ($test$plusargs("HAZARD_TEST")) begin
      hex_path = "build/hex/hazard_test.hex";
      trace_path = "build/trace/hazard_test.rtl.csv";
    end else if ($test$plusargs("CRC_TEST")) begin
      hex_path = "build/hex/crc_test.hex";
      trace_path = "build/trace/crc_test.rtl.csv";
    end else begin
      $fatal(1, "select +ISA_TEST, +HAZARD_TEST, or +CRC_TEST");
    end
    for (i = 0; i < 2048; i = i + 1) imem[i] = 32'h00000013;
    for (i = 0; i < 1024; i = i + 1) dmem[i] = 32'd0;
    $readmemh(hex_path, imem);
    trace_fd = $fopen(trace_path, "w");
    if (trace_fd == 0) $fatal(1, "cannot open trace output");
    $fdisplay(trace_fd, "step,pc,insn,rd_we,rd,rd_data,mem_we,mem_addr,mem_data");
    repeat (10) @(posedge clk);
    rst = 1'b0;
  end

  always @(posedge clk) begin
    if (rst) begin
      previous_mem_we <= 1'b0;
      previous_mem_addr <= 32'd0;
      previous_mem_data <= 32'd0;
      cycles <= 0;
      retire_step <= 0;
    end else begin
      cycles <= cycles + 1;
      if (cycles > 20000) $fatal(1, "CPU trace timeout after %0d retires", retire_step);

      if (retire_valid) begin
        if ((retire_insn[6:0] == 7'b0100011) != previous_mem_we)
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
            previous_mem_we,
            previous_mem_we ? previous_mem_addr : 0,
            previous_mem_we ? previous_mem_data : 0
        );
        retire_step <= retire_step + 1;

        if (previous_mem_we && previous_mem_addr == TEST_RESULT) begin
          $fclose(trace_fd);
          if (previous_mem_data != PASS_VALUE)
            $fatal(1, "firmware FAIL result=%08x", previous_mem_data);
          $display("RTL TRACE PASS: retires=%0d", retire_step + 1);
          $finish;
        end
      end

      previous_mem_we <= dmem_valid && dmem_we;
      previous_mem_addr <= dmem_addr;
      previous_mem_data <= dmem_wdata;
      if (dmem_valid && dmem_we && dmem_addr[31:12] == DATA_BASE[31:12])
        dmem[dmem_addr[11:2]] <= dmem_wdata;
    end
  end
endmodule

`default_nettype wire
