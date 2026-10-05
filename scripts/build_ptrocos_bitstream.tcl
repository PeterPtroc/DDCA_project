set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
if {[llength $argv] && [lindex $argv 0] eq "reuse"} {
    open_project [file join $root build ptrocos_vivado ptrocos.xpr]
    reset_run synth_1
} else {
    source [file join $script_dir create_ptrocos_project.tcl]
}
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "PtrocOS synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
puts "PTROCOS SYNTHESIS PASS"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "PtrocOS implementation failed: [get_property STATUS [get_runs impl_1]]"
}
set bit [file join $root build ptrocos_vivado ptrocos.runs impl_1 ptrocos_nexys_a7_top.bit]
if {![file isfile $bit]} { error "Missing PtrocOS bitstream $bit" }
file copy -force $bit [file join $root build ptrocos_vivado ptrocos_ddr2.bit]
puts "PTROCOS BITSTREAM PASS: [file join $root build ptrocos_vivado ptrocos_ddr2.bit]"
close_project
