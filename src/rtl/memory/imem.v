`default_nettype none
module imem #(
    parameter HEX_FILE = "build/hex/scope.hex"
) (
    input  wire clk,
    input  wire [31:0] addr,
    output reg  [31:0] rdata,
    input  wire [31:0] data_addr,
    output reg  [31:0] data_rdata
);
  // 64 KiB code space at 0x0000_0000.
  // The two logical read ports use opposite clock edges.  Keeping two ROM
  // images makes each port a canonical single-port BRAM template; inferring a
  // mixed-edge true-dual-port RAM is not supported by 7-series block RAM.
  (* ram_style = "block" *) reg [31:0] instruction_mem[0:16383];
  (* ram_style = "block" *) reg [31:0] data_mem[0:16383];
  integer i;
  initial begin
    for (i = 0; i < 16384; i = i + 1) begin
      instruction_mem[i] = 32'h00000013;
      data_mem[i] = 32'h00000013;
    end
    $readmemh(HEX_FILE, instruction_mem);
    $readmemh(HEX_FILE, data_mem);
  end
  // Read-only data port lets startup copy .data from its ROM load address and
  // lets C code access const data without unifying instruction/data traffic.
  // Instruction fetch keeps its falling-edge contract.  The independent
  // data-side port is sampled on the rising edge so loads get a full cycle.
  always @(negedge clk) begin
    rdata <= (addr[31:16] == 16'h0000) ?
             instruction_mem[addr[15:2]] : 32'h00000013;
  end
  always @(posedge clk) begin
    data_rdata <= (data_addr[31:16] == 16'h0000) ?
                  data_mem[data_addr[15:2]] : 32'd0;
  end
endmodule
`default_nettype wire
