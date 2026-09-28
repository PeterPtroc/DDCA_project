`default_nettype none
module hazard_unit (
    input wire ifid_valid, uses_rs1, uses_rs2,
    input wire [4:0] ifid_rs1, ifid_rs2,
    input wire idex_valid, idex_mem_re, input wire [4:0] idex_rd,
    output wire load_use_stall
);
    assign load_use_stall = ifid_valid && idex_valid && idex_mem_re && idex_rd != 0 &&
        ((uses_rs1 && ifid_rs1 == idex_rd) || (uses_rs2 && ifid_rs2 == idex_rd));
endmodule
`default_nettype wire
