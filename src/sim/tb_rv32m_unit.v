`default_nettype none
module tb_rv32m_unit;
  reg clk = 0, rst = 1, start = 0;
  reg [2:0] op = 0;
  reg [31:0] a = 0, b = 0;
  wire busy, done;
  wire [31:0] result;
  integer fd, status, cycles, tests = 0, i;
  reg [2:0] vector_op;
  reg [31:0] vector_a, vector_b, expected;
  rv32m_unit dut(.clk(clk), .rst(rst), .start(start), .op(op), .a(a), .b(b),
                 .busy(busy), .done(done), .result(result));
  always #5 clk = ~clk;

  task request;
    input [2:0] operation;
    input [31:0] left, right;
    begin
      @(negedge clk);
      op = operation; a = left; b = right; start = 1;
      @(negedge clk);
      start = 0;
    end
  endtask

  initial begin
    repeat (3) @(negedge clk);
    rst = 0;
    // 取消操作必须清除 busy/done，并防止随后错误地产生已取消请求的结果。
    request(4, 32'h80000000, 7);
    repeat (7) @(negedge clk);
    rst = 1;
    @(negedge clk);
    if (busy || done) $fatal(1, "reset did not cancel operation");
    rst = 0;
    repeat (36) begin
      @(negedge clk);
      if (busy || done) $fatal(1, "cancelled operation completed");
    end
    fd = $fopen("build/rv32m/vectors.txt", "r");
    if (!fd) $fatal(1, "missing RV32M vectors");
    status = $fscanf(fd, "%h %h %h %h\n", vector_op, vector_a, vector_b, expected);
    while (status == 4) begin
      request(vector_op, vector_a, vector_b);
      cycles = 0;
      while (!done && cycles < 34) begin
        // 忙碌期间，即使改变操作数或置位 start，也不得改变
        // 已锁存的请求，或额外产生一次完成事件。
        a = ~vector_a; b = ~vector_b; op = ~vector_op;
        start = busy && cycles == 3;
        @(negedge clk);
        cycles = cycles + 1;
      end
      start = 0;
      if (!done || busy || result !== expected)
        $fatal(1, "M mismatch op=%0d a=%08x b=%08x got=%08x expected=%08x cycles=%0d",
               vector_op, vector_a, vector_b, result, expected, cycles);
      @(negedge clk);
      if (done || busy) $fatal(1, "completion is not a single pulse");
      tests = tests + 1;
      status = $fscanf(fd, "%h %h %h %h\n", vector_op, vector_a, vector_b, expected);
    end
    $fclose(fd);
    if (tests != 5248) $fatal(1, "incomplete vector set: %0d", tests);
    $display("RV32M UNIT PASS: %0d vectors plus reset cancellation", tests);
    $finish;
  end
endmodule
`default_nettype wire
