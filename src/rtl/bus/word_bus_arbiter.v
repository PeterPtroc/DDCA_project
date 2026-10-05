`default_nettype none
// Round-robin CPU/DMA arbitration; grant is held through target completion.
module word_bus_arbiter (
    input wire clk, rst,
    input wire cpu_valid, cpu_we,
    input wire [31:0] cpu_addr, cpu_wdata,
    input wire [3:0] cpu_wstrb,
    output wire cpu_ready,
    output wire [31:0] cpu_rdata,
    output wire cpu_error,
    input wire dma_valid, dma_we,
    input wire [31:0] dma_addr, dma_wdata,
    input wire [3:0] dma_wstrb,
    output wire dma_ready,
    output wire [31:0] dma_rdata,
    output wire dma_error,
    output reg valid, we,
    output reg [31:0] addr, wdata,
    output reg [3:0] wstrb,
    input wire ready,
    input wire [31:0] rdata,
    input wire error
);
  reg owner, last_owner;
  assign cpu_ready=valid && !owner && ready;
  assign dma_ready=valid && owner && ready;
  assign cpu_rdata=rdata;
  assign dma_rdata=rdata;
  assign cpu_error=error;
  assign dma_error=error;
  always @(posedge clk) begin
    if(rst) begin
      valid<=0; we<=0; addr<=0; wdata<=0; wstrb<=0; owner<=0; last_owner<=1;
    end else if(valid) begin
      if(ready) begin valid<=0; last_owner<=owner; end
    end else if(cpu_valid && (!dma_valid || last_owner)) begin
      valid<=1; owner<=0; we<=cpu_we; addr<=cpu_addr; wdata<=cpu_wdata; wstrb<=cpu_wstrb;
    end else if(dma_valid) begin
      valid<=1; owner<=1; we<=dma_we; addr<=dma_addr; wdata<=dma_wdata; wstrb<=dma_wstrb;
    end
  end
endmodule
`default_nettype wire
