set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
set ptrocos_firmware ddr2
set reuse false
foreach arg $argv {
    if {$arg eq "reuse"} {set reuse true} elseif {$arg in {ddr2 text shell storage graphics media video elf}} {set ptrocos_firmware $arg} else {error "Unknown argument: $arg"}
}
if {$ptrocos_firmware eq "ddr2"} {set project_folder ptrocos_vivado} else {set project_folder ptrocos_${ptrocos_firmware}_vivado}
source [file join $script_dir build_guard.tcl]
set project_file [file join $root build $project_folder ptrocos.xpr]
if {$reuse && [ddca_guard prepare project $project_file $ptrocos_firmware] eq "ready"} {
    open_project $project_file
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
set board_top [expr {$ptrocos_firmware eq "elf" ? "ptrocos_elf_nexys_a7_top" : "ptrocos_nexys_a7_top"}]
set bit [file join $root build $project_folder ptrocos.runs impl_1 ${board_top}.bit]
if {![file isfile $bit]} { error "Missing PtrocOS bitstream $bit" }
file copy -force $bit [file join $root build $project_folder ptrocos_${ptrocos_firmware}.bit]
ddca_guard finish bitstream [file join $root build $project_folder ptrocos_${ptrocos_firmware}.bit] $ptrocos_firmware
puts "PTROCOS BITSTREAM PASS: [file join $root build $project_folder ptrocos_${ptrocos_firmware}.bit]"
close_project
