set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
set ptrocos_firmware ddr2
set reuse false
foreach arg $argv {
    if {$arg eq "reuse"} {set reuse true} elseif {$arg in {ddr2 text shell storage graphics media video}} {set ptrocos_firmware $arg} else {error "Unknown argument: $arg"}
}
if {$ptrocos_firmware eq "ddr2"} {set project_folder ptrocos_vivado} else {set project_folder ptrocos_${ptrocos_firmware}_vivado}
if {$reuse} {
    open_project [file join $root build $project_folder ptrocos.xpr]
    # Existing projects may predate the post-place ROM fanout hook.
    set rom_hook [file join $script_dir optimize_ptrocos_rom.tcl]
    if {![llength [get_files -quiet $rom_hook]]} {add_files -fileset utils_1 -norecurse $rom_hook}
    set_property STEPS.PLACE_DESIGN.TCL.POST $rom_hook [get_runs impl_1]
    set_property PROCESSING_ORDER LATE [get_files ptrocos_audio.xdc]
    set_property USED_IN_SYNTHESIS false [get_files ptrocos_audio.xdc]
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
set bit [file join $root build $project_folder ptrocos.runs impl_1 ptrocos_nexys_a7_top.bit]
if {![file isfile $bit]} { error "Missing PtrocOS bitstream $bit" }
file copy -force $bit [file join $root build $project_folder ptrocos_${ptrocos_firmware}.bit]
puts "PTROCOS BITSTREAM PASS: [file join $root build $project_folder ptrocos_${ptrocos_firmware}.bit]"
close_project
