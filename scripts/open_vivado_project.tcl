# Validate inputs before opening any existing project or run cache.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
set project_file [file join $root build vivado rv32_realtime_scope.xpr]
source [file join $script_dir check_firmware.tcl]
if {[ddca_guard prepare project $project_file] eq "ready"} {
    open_project $project_file
    source [file join $script_dir configure_firmware.tcl]
    source [file join $script_dir configure_timing.tcl]
    ddca_configure_guard $project_file freertos [file join $root build vivado rv32_realtime_scope.bit]
} else {
    source [file join $script_dir create_vivado_project.tcl]
}
puts "VIVADO PROJECT READY: $project_file"
