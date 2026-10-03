`default_nettype none
module clint (
    input wire clk,
    input wire rst,
    input wire valid,
    input wire we,
    input wire [3:0] wstrb,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output wire machine_timer_irq,
    output wire machine_software_irq
);
  localparam [31:0] MSIP_ADDR      = 32'h02000000;
  localparam [31:0] MTIMECMP_LO    = 32'h02004000;
  localparam [31:0] MTIMECMP_HI    = 32'h02004004;
  localparam [31:0] MTIME_LO       = 32'h0200bff8;
  localparam [31:0] MTIME_HI       = 32'h0200bffc;

  reg [63:0] mtime;
  reg [63:0] mtimecmp;
  reg msip;

  function [31:0] merge_bytes;
    input [31:0] old_value;
    input [31:0] new_value;
    input [3:0] enables;
    begin
      merge_bytes = old_value;
      if (enables[0]) merge_bytes[7:0] = new_value[7:0];
      if (enables[1]) merge_bytes[15:8] = new_value[15:8];
      if (enables[2]) merge_bytes[23:16] = new_value[23:16];
      if (enables[3]) merge_bytes[31:24] = new_value[31:24];
    end
  endfunction

  always @* begin
    case (addr)
      MSIP_ADDR:   rdata = {31'd0, msip};
      MTIMECMP_LO: rdata = mtimecmp[31:0];
      MTIMECMP_HI: rdata = mtimecmp[63:32];
      MTIME_LO:    rdata = mtime[31:0];
      MTIME_HI:    rdata = mtime[63:32];
      default:     rdata = 32'd0;
    endcase
  end

  assign machine_timer_irq = (mtime >= mtimecmp);
  assign machine_software_irq = msip;

  always @(posedge clk) begin
    if (rst) begin
      mtime <= 64'd0;
      mtimecmp <= 64'hffffffffffffffff;
      msip <= 1'b0;
    end else begin
      if (valid && we && addr == MTIME_LO)
        mtime <= {mtime[63:32], merge_bytes(mtime[31:0], wdata, wstrb)};
      else if (valid && we && addr == MTIME_HI)
        mtime <= {merge_bytes(mtime[63:32], wdata, wstrb), mtime[31:0]};
      else
        mtime <= mtime + 64'd1;

      if (valid && we && addr == MTIMECMP_LO)
        mtimecmp[31:0] <= merge_bytes(mtimecmp[31:0], wdata, wstrb);
      if (valid && we && addr == MTIMECMP_HI)
        mtimecmp[63:32] <= merge_bytes(mtimecmp[63:32], wdata, wstrb);
      if (valid && we && addr == MSIP_ADDR && wstrb[0])
        msip <= wdata[0];
    end
  end
endmodule
`default_nettype wire
