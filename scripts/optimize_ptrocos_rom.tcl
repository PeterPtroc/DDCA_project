# Post-place only: Vivado 2024.2 rejects forced replication after routing.
# Address fanout dominates the CPU-posedge -> ROM-negedge half-cycle path.
# Replication changes the physical netlist only; RTL and clock phases are fixed.
set pc_registers [get_cells -hier -quiet -regexp {.*soc/cpu/pc_reg\[([2-9]|1[0-5])\]$}]
if {[llength $pc_registers]!=14} {error "Missing instruction address registers: $pc_registers"}
set outputs [get_pins -of_objects $pc_registers -filter {REF_PIN_NAME == Q}]
set nets [get_nets -of_objects $outputs]
if {[llength $nets]!=14} {error "Ambiguous instruction address nets: $nets"}
puts "PTROCOS POST-PLACE ROM ADDRESS REPLICATION: $nets"
phys_opt_design -force_replication_on_nets $nets
