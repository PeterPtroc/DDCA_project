`default_nettype none
// Independent 16 KiB writable application window. Both BRAM ports use the
// falling edge: instruction fetch keeps the frozen CPU's original contract.
// CPU data transactions cross through a held-payload mailbox and wait for the
// registered BRAM result. No mixed-edge RAM inference or CPU edits are needed.
module ptrocos_app_memory (
    input wire clk,rst,
    input wire [31:0] instruction_addr,
    output reg [31:0] instruction_data,
    input wire valid,we,
    input wire [31:0] addr,wdata,
    input wire [3:0] wstrb,
    output wire ready,
    output wire [31:0] rdata,
    output wire error
);
  wire app_clk=~clk;
  wire target_valid,target_we;
  wire [31:0] target_addr,target_wdata;
  wire [3:0] target_wstrb;
  reg target_ready,target_error,seen;
  reg [31:0] target_rdata;
  word_bus_cdc register_cdc (
      .source_clk(clk),.source_rst(rst),.source_valid(valid),.source_we(we),
      .source_addr(addr),.source_wdata(wdata),.source_wstrb(wstrb),
      .source_ready(ready),.source_rdata(rdata),.source_error(error),
      .target_clk(app_clk),.target_rst(rst),.target_valid(target_valid),.target_we(target_we),
      .target_addr(target_addr),.target_wdata(target_wdata),.target_wstrb(target_wstrb),
      .target_ready(target_ready),.target_rdata(target_rdata),.target_error(target_error)
  );
  (* ram_style="block" *) reg [31:0] memory[0:4095];
  wire instruction_selected=instruction_addr[31:14]==18'h00004 && instruction_addr[1:0]==0;
  wire selected=target_addr[31:14]==18'h00004;
  wire [11:0] instruction_index=instruction_addr[13:2],data_index=target_addr[13:2];
  always @(posedge app_clk) begin
    instruction_data<=(!rst && instruction_selected) ? memory[instruction_index] : 32'd0;
  end
  // The second BRAM port registers the read and applies each byte write once.
  always @(posedge app_clk) begin
    if(!rst && target_valid && !seen) begin
      target_rdata<=selected ? memory[data_index] : 32'd0;
      if(selected && target_we) begin
        if(target_wstrb[0]) memory[data_index][7:0]<=target_wdata[7:0];
        if(target_wstrb[1]) memory[data_index][15:8]<=target_wdata[15:8];
        if(target_wstrb[2]) memory[data_index][23:16]<=target_wdata[23:16];
        if(target_wstrb[3]) memory[data_index][31:24]<=target_wdata[31:24];
      end
    end
  end
  always @(posedge app_clk) begin
    if(rst) begin target_ready<=0;target_error<=0;seen<=0;end
    else if(!target_valid) begin target_ready<=0;seen<=0;end
    else if(!seen) begin
      seen<=1;target_ready<=1;target_error<=!selected;
    end
  end
endmodule
`default_nettype wire
