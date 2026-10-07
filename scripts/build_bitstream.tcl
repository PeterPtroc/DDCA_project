# Compatibility entry for the unchanged README quick start.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir create_vivado_project.tcl]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "PtrocOS synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "PtrocOS implementation failed: [get_property STATUS [get_runs impl_1]]"
}
puts "BITSTREAM PASS: [file join $root build vivado rv32_realtime_scope.bit]"
close_project
