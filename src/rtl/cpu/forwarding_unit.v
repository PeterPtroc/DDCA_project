`default_nettype none
module forwarding_unit (
    input wire [4:0] rs1,
    rs2,
    exmem_rd,
    memwb_rd,
    input wire exmem_we,
    memwb_we,
    exmem_is_load,
    output reg [1:0] fwd_a,
    fwd_b
);
  always @* begin
    fwd_a = 0;
    fwd_b = 0;
    if (exmem_we && !exmem_is_load && exmem_rd != 0 && exmem_rd == rs1) fwd_a = 2'd1;
    else if (memwb_we && memwb_rd != 0 && memwb_rd == rs1) fwd_a = 2'd2;
    if (exmem_we && !exmem_is_load && exmem_rd != 0 && exmem_rd == rs2) fwd_b = 2'd1;
    else if (memwb_we && memwb_rd != 0 && memwb_rd == rs2) fwd_b = 2'd2;
  end
endmodule
`default_nettype wire
