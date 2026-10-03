`default_nettype none
module hazard_unit (
    input wire ifid_valid,
    uses_rs1,
    uses_rs2,
    input wire [4:0] ifid_rs1,
    ifid_rs2,
    input wire idex_valid,
    idex_mem_re,
    input wire [4:0] idex_rd,
    input wire exmem_valid,
    exmem_mem_re,
    input wire [4:0] exmem_rd,
    output wire load_use_stall
);
  wire idex_load_hazard = idex_valid && idex_mem_re && idex_rd != 0 &&
      ((uses_rs1 && ifid_rs1 == idex_rd) ||
       (uses_rs2 && ifid_rs2 == idex_rd));
  wire exmem_load_hazard = exmem_valid && exmem_mem_re && exmem_rd != 0 &&
      ((uses_rs1 && ifid_rs1 == exmem_rd) ||
       (uses_rs2 && ifid_rs2 == exmem_rd));

  // Loads use a synchronous data port and therefore remain unavailable while
  // they occupy both EX/MEM and the request stage.
  assign load_use_stall = ifid_valid &&
      (idex_load_hazard || exmem_load_hazard);
endmodule
`default_nettype wire
