# Used by open_vivado_gui.bat; refresh the project on every launch.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set project_file [file join $root build vivado rv32_realtime_scope.xpr]
source [file join $script_dir check_firmware.tcl]
if {[file exists $project_file]} {
    open_project $project_file
} else {
    source [file join $script_dir create_vivado_project.tcl]
}
source [file join $script_dir configure_firmware.tcl]
source [file join $script_dir configure_timing.tcl]
puts "VIVADO PROJECT READY: $project_file"
