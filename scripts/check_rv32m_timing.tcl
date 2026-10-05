# Standalone out-of-context 100 MHz check. This does not change the board project.
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set out [file join $root build rv32m timing]
file mkdir $out
set reuse [expr {[llength $argv] > 0 && [lindex $argv 0] eq "reuse"}]
if {$reuse} {
    open_checkpoint [file join $out rv32im_core_routed.dcp]
    reset_timing
} else {
create_project -in_memory -part xc7a100tcsg324-1
foreach name {alu crc16_unit decoder hazard_unit imm_gen regfile rv32m_unit rv32im_decoder rv32im_core} {
    read_verilog [file join $root src rtl cpu ${name}.v]
}
synth_design -top rv32im_core -part xc7a100tcsg324-1 -mode out_of_context
}
create_clock -name cpu_clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks cpu_clk]
# Interface timing belongs to the surrounding SoC/BRAM/MIG project. This check
# constrains and accepts only register-to-register paths inside the CPU.
if {!$reuse} {
opt_design
place_design -directive ExtraPostPlacementOpt
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
}
report_timing_summary -file [file join $out timing_summary_routed.rpt]
report_timing -max_paths 10 -file [file join $out timing_paths.rpt]
report_utilization -file [file join $out utilization.rpt]
write_checkpoint -force [file join $out rv32im_core_routed.dcp]
set setup [get_timing_paths -from [all_registers] -to [all_registers] -max_paths 1 -delay_type max]
set hold [get_timing_paths -from [all_registers] -to [all_registers] -max_paths 1 -delay_type min]
if {[llength $setup] == 0 || [llength $hold] == 0} { error "Missing setup/hold paths" }
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
puts "RV32M OOC INTERNAL TIMING: WNS=$wns ns WHS=$whs ns"
if {$wns < 0.100 || $whs < 0.000} { error "RV32M OOC timing failed" }
puts "RV32M OOC TIMING PASS (board integration still needs its own timing check)"
